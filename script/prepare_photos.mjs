import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { chromium } from "playwright";

const [output, ...inputs] = process.argv.slice(2);
if (!output || !inputs.length)
  throw new Error("Usage: node script/prepare_photos.mjs OUTPUT_DIRECTORY INPUT_PHOTO...");
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const bundle = await build({
  entryPoints: [join(root, "app/javascript/search/preparePhoto.js")],
  bundle: true,
  format: "esm",
  write: false,
});
const server = createServer((request, response) => {
  if (request.url === "/preparePhoto.js") {
    response.setHeader("Content-Type", "text/javascript");
    response.end(bundle.outputFiles[0].text);
  } else if (request.url === "/") {
    response.setHeader("Content-Type", "text/html");
    response.end('<!doctype html><title>Local photo preparation</title><input type="file">');
  } else {
    response.writeHead(404);
    response.end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  // Uses installed Chrome by default. Set PHOTO_BROWSER=chromium after installing Playwright Chromium if needed.
  browser = await chromium.launch({
    channel: process.env.PHOTO_BROWSER === "chromium" ? undefined : "chrome",
  });
  const page = await browser.newPage();
  await page.route("**/*", (route) =>
    route.request().url().startsWith(`${origin}/`) ? route.continue() : route.abort(),
  );
  await page.goto(origin);
  await mkdir(output, { recursive: true });
  for (const input of inputs) {
    await page.locator("input").setInputFiles(resolve(input));
    const prepared = await page.evaluate(async () => {
      const { preparePhoto } = await import("/preparePhoto.js");
      const result = await preparePhoto(document.querySelector("input").files[0]);
      const bytes = new Uint8Array(await result.blob.arrayBuffer());
      let binary = "";
      for (const byte of bytes) binary += String.fromCharCode(byte);
      return {
        base64: btoa(binary),
        width: result.width,
        height: result.height,
        quality: result.quality,
        recipe: result.recipe,
        source: result.source,
        browser: navigator.userAgent,
      };
    });
    const bytes = Buffer.from(prepared.base64, "base64");
    delete prepared.base64;
    const name = `${basename(input).replace(/\.[^.]+$/, "")}-prepared`;
    const hash = (data) => createHash("sha256").update(data).digest("hex");
    const metadata = {
      ...prepared,
      sourceSha256: hash(await readFile(input)),
      sha256: hash(bytes),
      bytes: bytes.length,
    };
    await writeFile(join(output, `${name}.jpg`), bytes, { flag: "wx" });
    await writeFile(join(output, `${name}.json`), `${JSON.stringify(metadata, null, 2)}\n`, {
      flag: "wx",
    });
    console.log(
      `${name}: ${bytes.length} bytes, ${prepared.width}x${prepared.height}, ${prepared.recipe}`,
    );
  }
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}

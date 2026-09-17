import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  inspectPhoto,
  PHOTO_RECIPE,
  preparePhoto,
} from "../../app/javascript/search/preparePhoto.js";

for (const [format, type] of [
  ["jpg", "image/jpeg"],
  ["png", "image/png"],
  ["webp", "image/webp"],
]) {
  test(`recognizes ${format} dimensions from bytes`, async () => {
    const bytes = await readFile(new URL(`../fixtures/files/photo.${format}`, import.meta.url));
    assert.deepEqual(inspectPhoto(bytes, type), { type, width: 24, height: 16 });
    assert.throws(() => inspectPhoto(bytes, "image/gif"), { code: "unsupported" });
  });
}

test("rejects corrupt and unsupported headers before decoding", () => {
  for (const bytes of [
    new Uint8Array(),
    new TextEncoder().encode("<svg/>"),
    new Uint8Array([255, 216, 255]),
  ]) {
    assert.throws(() => inspectPhoto(bytes));
  }
});

test("rejects oversized sources and pixel headers before bitmap allocation", async () => {
  globalThis.createImageBitmap = () => assert.fail("must not decode");
  await assert.rejects(preparePhoto({ size: PHOTO_RECIPE.maxSourceBytes + 1 }), {
    code: "too_large",
  });
  const bytes = await readFile(new URL("../fixtures/files/photo.png", import.meta.url));
  bytes.writeUInt32BE(5000, 16);
  bytes.writeUInt32BE(4001, 20);
  await assert.rejects(preparePhoto(new Blob([bytes], { type: "image/png" })), {
    code: "dimensions",
  });
  delete globalThis.createImageBitmap;
});

test("rejects animated PNG and WebP containers", async () => {
  const png = await readFile(new URL("../fixtures/files/photo.png", import.meta.url));
  const animation = Buffer.alloc(20);
  animation.writeUInt32BE(8);
  animation.write("acTL", 4);
  assert.throws(
    () => inspectPhoto(Buffer.concat([png.subarray(0, 33), animation, png.subarray(33)])),
    { code: "animated" },
  );
  const webp = Buffer.alloc(30);
  webp.write("RIFF");
  webp.writeUInt32LE(22, 4);
  webp.write("WEBPVP8X", 8);
  webp.writeUInt32LE(10, 16);
  webp[20] = 2;
  assert.throws(() => inspectPhoto(webp), { code: "animated" });
});

test("accepts only capped JPEG encoder output and closes bitmap on success and failure", async () => {
  const bytes = await readFile(new URL("../fixtures/files/photo.png", import.meta.url));
  for (const success of [true, false]) {
    let closed = false;
    let calls = 0;
    globalThis.createImageBitmap = async () => ({
      width: 24,
      height: 16,
      close: () => {
        closed = true;
      },
    });
    globalThis.document = {
      createElement: () => ({
        getContext: () => ({ fillRect() {}, drawImage() {} }),
        toBlob(callback, type) {
          calls++;
          callback(
            new Blob([new Uint8Array(success && calls === 3 ? 400_000 : 450_001)], { type }),
          );
        },
      }),
    };
    try {
      const promise = preparePhoto(new Blob([bytes], { type: "image/png" }));
      if (success) {
        const prepared = await promise;
        assert.equal(prepared.blob.size, 400_000);
        assert.equal(prepared.recipe, "jpeg-v1");
        assert.equal(calls, 3);
      } else {
        await assert.rejects(promise, { code: "compression" });
        assert.equal(calls, PHOTO_RECIPE.resizePasses * PHOTO_RECIPE.qualities.length);
      }
      assert.equal(closed, true);
    } finally {
      delete globalThis.createImageBitmap;
      delete globalThis.document;
    }
  }
});

test("cancellation stops work before reading a file", async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(
    preparePhoto(
      { size: 1, arrayBuffer: () => assert.fail("must not read") },
      { signal: controller.signal },
    ),
    { name: "AbortError" },
  );
});

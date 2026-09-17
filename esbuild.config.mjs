import * as esbuild from "esbuild";

const options = {
  entryPoints: ["app/javascript/application.jsx"],
  bundle: true,
  outdir: "app/assets/builds",
  publicPath: "/assets",
  format: "esm",
  platform: "browser",
  target: ["es2022"],
  jsx: "automatic",
  minify: true,
  define: { "process.env.NODE_ENV": '"production"' },
  logLevel: "info",
};

if (process.argv.includes("--watch")) {
  const context = await esbuild.context(options);
  await context.watch();
} else {
  await esbuild.build(options);
}

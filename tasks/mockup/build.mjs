import { build } from 'esbuild';
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const result = await build({
  absWorkingDir: fileURLToPath(new URL('.', import.meta.url)),
  entryPoints: ['main.jsx'],
  bundle: true,
  write: false,
  minify: true,
  format: 'iife',
  target: 'es2020',
  jsx: 'automatic',
  loader: { '.jpg': 'dataurl' },
  define: { 'process.env.NODE_ENV': '"production"' },
  legalComments: 'inline',
});

const script = result.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
const html = `<!doctype html>
<!-- Generated from tasks/mockup/main.jsx. Rebuild with npm --prefix tasks/mockup run build. -->
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>LooksAlike — Material UI mockup</title>
  <link rel="icon" href="data:,">
  <style>body{margin:0;background:#f5f2eb;color:#292e28}</style>
</head>
<body>
  <div id="root"></div>
  <noscript>Enable JavaScript to use this interactive mockup.</noscript>
  <script>${script}</script>
</body>
</html>
`;

await writeFile(new URL('../ui-mockup-looksalike-demo.html', import.meta.url), html);
console.log(`Built standalone Material UI mockup (${Math.round(Buffer.byteLength(html) / 1024)} KB).`);

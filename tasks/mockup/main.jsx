import { createRoot } from 'react-dom/client';
import { Box, CssBaseline, ThemeProvider, Typography } from '@mui/material';
import SearchApp from '../../app/javascript/search/SearchApp.jsx';
import theme from '../../app/javascript/search/theme.js';
import snapshot from '../../app/javascript/search/modernSofa.json';

function pause(ms, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(signal.reason); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, ms);
    signal.addEventListener('abort', abort, { once: true });
    if (signal.aborted) abort();
  });
}
// Timed progress is confined to this standalone design preview.
async function previewSearch(_blob, { signal, onStage, example }) {
  signal.throwIfAborted();
  if (example) return snapshot;
  for (const stage of ['upload', 'lens', 'vision', 'ebay', 'filter']) {
    signal.throwIfAborted();
    onStage({ type: 'stage', stage, status: 'started' });
    await pause(stage === 'filter' ? 500 : 1800, signal);
    onStage({ type: 'stage', stage, status: 'complete' });
  }
  throw new Error('This preview makes no live searches. Try the example to see the recorded eBay results.');
}
createRoot(document.getElementById('root')).render(<ThemeProvider theme={theme}>
  <CssBaseline />
  <Box sx={{ position: 'absolute', top: 12, left: 16, right: 16 }}><Typography sx={{ fontSize: 11 }} color="text.secondary">Design preview · Uploads model progress with timers. Only the example replays historical results. No provider calls.</Typography></Box>
  <SearchApp search={previewSearch} preview />
</ThemeProvider>);

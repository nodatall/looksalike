import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import examplePhoto from './assets/victorian-purple-couch.jpg';
import SearchWalkthrough from './SearchWalkthrough.jsx';
import {
  Accordion, AccordionDetails, AccordionSummary, Box, Button, Card,
  CardContent, CircularProgress, CssBaseline, TextField,
  ThemeProvider, Typography, createTheme, useMediaQuery,
} from '@mui/material';

const theme = createTheme({
  palette: {
    primary: { main: '#36563d' },
    background: { default: '#f5f2eb', paper: '#fffefa' },
    text: { primary: '#292e28', secondary: '#697064' },
    divider: '#d8dbcf',
    error: { main: '#914c32' },
  },
  typography: {
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    button: { textTransform: 'none' },
    h1: {
      fontFamily: 'Georgia, "Times New Roman", serif', fontWeight: 400,
      fontSize: 'clamp(30px, 4vw, 42px)', lineHeight: 1.15, letterSpacing: '-.045em',
    },
  },
  shape: { borderRadius: 7 },
  motion: { reducedMotion: 'system' },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        '@media (prefers-reduced-motion: reduce)': {
          '.MuiCircularProgress-root, .MuiCircularProgress-circle': { animation: 'none !important' },
        },
      },
    },
  },
});

const items = [
  ['Wood-frame lounge chair', 'chair', '#e5e5dc', 'San Francisco, CA'],
  ['Slender accent chair', 'slim', '#e6ded4', 'Oakland, CA'],
  ['Soft, rounded armchair', 'wide', '#e2e6e1', 'Berkeley, CA'],
  ['Compact reading chair', 'wide', '#e9e0d2', 'Daly City, CA'],
  ['Open-arm lounge chair', 'chair', '#e5e0db', 'San Mateo, CA'],
  ['Upholstered accent chair', 'slim', '#dedfd4', 'Alameda, CA'],
];
const validZip = value => /^[0-9]{5}$/.test(value.trim());
const resultsStorageKey = 'looksalike.mockup.results.v1';

function restoreResults() {
  try {
    const saved = JSON.parse(sessionStorage.getItem(resultsStorageKey));
    const validPhoto = saved?.photoDataUrl === null ||
      (typeof saved?.photoDataUrl === 'string' && /^data:image\/(jpeg|png|webp);base64,/.test(saved.photoDataUrl));
    if (saved?.version === 1 && validZip(saved.zip) && validPhoto) return saved;
  } catch {
    // A missing or unreadable saved view should still leave the mockup usable.
  }
  return null;
}

function photoForReload(image) {
  const scale = Math.min(1, 640 / Math.max(image.naturalWidth, image.naturalHeight));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
  canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
  const context = canvas.getContext('2d');
  context.fillStyle = '#fffefa';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL('image/jpeg', .8);
}

const centeredScreen = {
  minHeight: '100svh', display: 'grid', placeItems: 'center', px: 3, py: 5,
  '@media (max-width:620px)': { px: '22px', py: '70px' },
};
const textButton = { textDecoration: 'underline', textUnderlineOffset: '3px' };

function Chair({ variant = 'chair', label }) {
  return (
    <svg viewBox="0 0 300 240" role={label ? 'img' : undefined} aria-label={label}
      aria-hidden={label ? undefined : true} style={{ display: 'block', width: '100%', height: '100%' }}>
      <ellipse cx="153" cy="218" rx="94" ry="10" fill="#2f3226" opacity=".09" />
      {variant === 'wide' ? <>
        <path d="m91 166-9 48m129-48 9 48" stroke="#6e4f34" strokeWidth="9" strokeLinecap="round" />
        <rect x="82" y="59" width="132" height="112" rx="24" fill="#9c9e84" />
        <path d="M90 65q-25 13-13 84m129-84q22 15 16 85" fill="none" stroke="#85896e" strokeWidth="13" />
        <rect x="75" y="130" width="151" height="51" rx="17" fill="#b5b69a" />
        <path d="M70 111v60m160-60v60" stroke="#7f6043" strokeWidth="12" strokeLinecap="round" />
      </> : variant === 'slim' ? <>
        <path d="M100 142 80 215m119-73 20 73M87 149l120 10M102 67l-9 76m104-76 10 82" fill="none" stroke="#775138" strokeWidth="9" strokeLinecap="round" />
        <rect x="101" y="54" width="95" height="90" rx="10" fill="#aa785d" />
        <path d="M110 65h76M111 74h74" stroke="#d4a68c" strokeWidth="2" />
        <path d="m90 140 118-2 10 29H84Z" fill="#c08d6e" />
        <path d="m69 121 36 5m91 0 35-7M77 122l7 62m139-64-7 64" fill="none" stroke="#886142" strokeWidth="8" strokeLinecap="round" />
      </> : <>
        <path d="M98 134 79 214M200 134l18 80M90 148h117" fill="none" stroke="#795439" strokeWidth="10" strokeLinecap="round" />
        <path d="m91 164 15-100q2-12 14-12h65q17 0 19 17l10 92" fill="#a99771" stroke="#827251" strokeWidth="2" />
        <path d="m92 122 117-1 4 39H91Z" fill="#c1af87" />
        <path d="M110 64h76M115 73h67" stroke="#ddcfac" strokeWidth="2" opacity=".8" />
        <path d="m67 126 34 7m103-1 30-8M74 127l8 51m146-53-10 54M83 178l15-14m120 15-13-15" fill="none" stroke="#886142" strokeWidth="9" strokeLinecap="round" />
      </>}
    </svg>
  );
}

function Photo({ photo, compact = false }) {
  return (
    <Box component="span" sx={{
      height: compact ? 80 : '100%', width: compact ? 80 : '100%', flexShrink: 0,
      border: compact ? 1 : 0, borderColor: 'divider',
      borderRadius: compact ? '9px' : 'inherit', overflow: 'hidden', bgcolor: '#e6dfd0',
      display: 'grid', placeItems: 'center',
      '@media (max-width:620px)': compact
        ? { width: 64, height: 64 }
        : {},
    }}>
      <Box component="img" src={photo?.url || examplePhoto}
        alt={photo?.url ? 'Selected furniture photo' : 'Example Victorian purple couch'}
        sx={{ display: 'block', width: '100%', height: '100%', minHeight: 0, objectFit: 'contain' }} />
    </Box>
  );
}

function ZipField({ value, onChange, error, disabled, inputRef, onSearch }) {
  return <TextField id="zip-code" label="ZIP code" name="zip" type="text" required fullWidth
    variant="outlined" placeholder="e.g. 10001" value={value} disabled={disabled}
    onChange={onChange} inputRef={inputRef} error={Boolean(error)} helperText={error || undefined}
    onKeyDown={event => {
      if (event.key === 'Enter' && onSearch) { event.preventDefault(); onSearch(); }
    }}
    slotProps={{
      inputLabel: { required: false },
      htmlInput: { inputMode: 'numeric', autoComplete: 'postal-code', maxLength: 5, pattern: '[0-9]{5}' },
      formHelperText: { role: error ? 'alert' : undefined },
    }}
    sx={{ textAlign: 'left', '& .MuiOutlinedInput-root': { bgcolor: 'background.paper' } }} />;
}

function ListingCard({ item: [title, variant, color, location] }) {
  return <Card component="article" variant="outlined" sx={{ borderRadius: '8px' }}>
    <Box sx={{ height: 164, bgcolor: color, p: '14px', '@media (max-width:620px)': { height: 142 } }}>
      <Chair variant={variant} />
    </Box>
    <CardContent sx={{ p: '13px 14px 14px', '&:last-child': { pb: '14px' }, '@media (max-width:620px)': { p: '11px' } }}>
      <Typography component="h3" sx={{ fontSize: 13, fontWeight: 600, mb: .5 }}>{title}</Typography>
      <Typography color="text.secondary" sx={{ fontSize: 12, mb: 1 }}>{location}</Typography>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: .75,
        borderTop: 1, borderColor: 'divider', pt: 1,
        '@media (max-width:620px)': { flexDirection: 'column', alignItems: 'start' } }}>
        <Typography color="text.secondary" sx={{ fontSize: 10 }}>Price if provided</Typography>
        <Button size="small" disabled aria-label="Open example listing, unavailable in preview"
          sx={{ fontSize: 11, minWidth: 0, p: 0 }}>View listing ↗</Button>
      </Box>
    </CardContent>
  </Card>;
}

function App() {
  const [savedResults] = useState(restoreResults);
  const [screen, setScreen] = useState(savedResults ? 'results' : 'entry');
  const [zip, setZip] = useState(savedResults?.zip || '');
  const [requestedZip, setRequestedZip] = useState(savedResults?.zip || '');
  const [photo, setPhoto] = useState(savedResults
    ? { url: savedResults.photoDataUrl, storageUrl: savedResults.photoDataUrl } : null);
  const [explanationExpanded, setExplanationExpanded] = useState(savedResults?.explanationExpanded === true);
  const [loading, setLoading] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [zipError, setZipError] = useState('');
  const [uploadError, setUploadError] = useState('');
  const [status, setStatus] = useState('');
  const fileInput = useRef(null), zipInput = useRef(null), findButton = useRef(null);
  const uploadButton = useRef(null), resultsTitle = useRef(null), firstRender = useRef(true);
  const selectionVersion = useRef(0), pendingPhoto = useRef(null), activeURL = useRef(null), timer = useRef(null);
  const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');

  function cancelSelection() {
    selectionVersion.current++;
    if (pendingPhoto.current) {
      pendingPhoto.current.image.src = '';
      URL.revokeObjectURL(pendingPhoto.current.url);
      pendingPhoto.current = null;
    }
  }
  function releasePhoto() {
    if (activeURL.current) URL.revokeObjectURL(activeURL.current);
    activeURL.current = null;
  }
  function cancelSearch() {
    clearTimeout(timer.current);
    timer.current = null;
    setLoading(false);
  }
  function previewPhoto(url = null, storageUrl = null) {
    cancelSearch();
    releasePhoto();
    activeURL.current = url;
    setPhoto({ url, storageUrl });
    setUploadError('');
    setStatus('Photo ready to preview.');
  }
  function showError(message) { setUploadError(message); setStatus(''); }

  async function selectPhoto(file) {
    cancelSelection();
    const version = selectionVersion.current;
    setUploadError('');
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      showError('Choose a JPEG, PNG, or WebP photo.'); return;
    }
    if (file.size > 10 * 1024 * 1024) {
      showError('Choose a photo no larger than 10 MB.'); return;
    }
    const url = URL.createObjectURL(file);
    const image = new Image();
    pendingPhoto.current = { image, url };
    image.src = url;
    try {
      await image.decode();
      if (version !== selectionVersion.current) return;
      pendingPhoto.current = null;
      if (!image.naturalWidth || !image.naturalHeight || image.naturalWidth * image.naturalHeight > 20000000) {
        URL.revokeObjectURL(url);
        showError('Choose a photo with no more than 20 megapixels.'); return;
      }
      previewPhoto(url, photoForReload(image));
    } catch {
      if (version !== selectionVersion.current) return;
      pendingPhoto.current = null;
      URL.revokeObjectURL(url);
      showError('That photo could not be opened. Try another image.');
    }
  }
  function useExample() {
    cancelSelection();
    if (!zip.trim()) setZip('94103');
    setZipError('');
    previewPhoto();
  }
  function search() {
    if (!photo || timer.current !== null) return;
    if (!validZip(zip)) {
      setZipError('Enter a five-digit US ZIP code.');
      zipInput.current?.focus();
      return;
    }
    setZip(zip.trim());
    setRequestedZip(zip.trim());
    setLoading(true);
    setStatus('Finding similar items.');
    timer.current = setTimeout(() => {
      timer.current = null;
      setLoading(false);
      setScreen('results');
      setStatus('Six illustrative items are ready.');
    }, 2200);
  }
  function startOver() {
    cancelSelection(); cancelSearch(); releasePhoto();
    setPhoto(null); setUploadError(''); setZipError(''); setStatus(''); setDragging(false);
    setExplanationExpanded(false);
    try { sessionStorage.removeItem(resultsStorageKey); } catch { /* Storage may be unavailable. */ }
    setScreen('entry');
  }

  useEffect(() => {
    if (screen !== 'results') return;
    try {
      sessionStorage.setItem(resultsStorageKey, JSON.stringify({
        version: 1, zip: requestedZip, photoDataUrl: photo?.storageUrl || null, explanationExpanded,
      }));
    } catch {
      setStatus('Results are ready, but this browser could not save the view for reload.');
    }
  }, [screen, requestedZip, photo, explanationExpanded]);

  useEffect(() => {
    if (firstRender.current) { firstRender.current = false; return; }
    if (screen === 'entry') {
      if (photo) (validZip(zip) ? findButton : zipInput).current?.focus({ preventScroll: true });
      else uploadButton.current?.focus({ preventScroll: true });
    }
    if (screen === 'results') {
      resultsTitle.current?.focus();
      window.scrollTo({ top: 0, behavior: 'instant' });
    }
  }, [screen, photo]);

  useEffect(() => {
    const preventNavigation = event => event.preventDefault();
    const cleanup = () => {
      cancelSelection(); releasePhoto(); clearTimeout(timer.current); timer.current = null;
    };
    document.addEventListener('dragover', preventNavigation);
    document.addEventListener('drop', preventNavigation);
    window.addEventListener('pagehide', cleanup);
    return () => {
      cleanup();
      document.removeEventListener('dragover', preventNavigation);
      document.removeEventListener('drop', preventNavigation);
      window.removeEventListener('pagehide', cleanup);
    };
  }, []);

  const zipProps = {
    value: zip, error: zipError, inputRef: zipInput, disabled: loading,
    onChange: event => { setZip(event.target.value); setZipError(''); },
  };

  return <Box component="main">
    <input id="photo-input" ref={fileInput} type="file" accept="image/jpeg,image/png,image/webp" hidden
      onChange={event => {
        const file = event.target.files[0];
        event.target.value = '';
        if (file) selectPhoto(file);
      }} />
    {screen === 'entry' && <Box component="section" aria-label="Choose a furniture photo" aria-busy={loading} sx={centeredScreen}>
      <Box sx={{ width: 'min(100%, 520px)', textAlign: 'center' }}>
        <Typography component="h1" variant="h1" sx={{ mb: 3.5, textWrap: 'balance' }}>
          Find similar items on Craigslist near you
        </Typography>
        <Box sx={{ mb: 3 }}><ZipField {...zipProps} onSearch={photo ? search : undefined} /></Box>
        <Button id="drop-zone" variant="outlined" fullWidth ref={uploadButton} disabled={loading}
          aria-label={photo ? 'Choose another furniture photo' : 'Upload a furniture photo'}
          onClick={() => fileInput.current?.click()}
          onDragOver={event => { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; setDragging(true); }}
          onDragLeave={event => { if (!event.currentTarget.contains(event.relatedTarget)) setDragging(false); }}
          onDrop={event => {
            event.preventDefault(); setDragging(false);
            if (loading) return;
            const files = event.dataTransfer.files;
            if (files.length !== 1) { cancelSelection(); showError('Choose one furniture photo at a time.'); return; }
            selectPhoto(files[0]);
          }}
          sx={{ height: 310, p: photo ? 0 : '48px 24px', borderStyle: 'dashed', borderColor: '#9daa92',
            borderRadius: '14px', bgcolor: dragging ? '#e6ebde' : 'rgba(255,255,255,.35)',
            color: 'text.primary', display: 'flex', flexDirection: 'column', gap: '18px', overflow: 'hidden',
            '&:hover': { borderStyle: 'dashed', bgcolor: '#e6ebde' },
            '@media (max-width:620px)': { height: 280 } }}>
          {photo ? <Photo photo={photo} /> : <>
          <Box component="span" sx={{ width: 58, height: 58, display: 'grid', placeItems: 'center',
            color: 'primary.main', borderRadius: '50%', bgcolor: '#e6ebde' }} aria-hidden="true">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
              <rect x="3" y="4" width="18" height="16" rx="3" /><circle cx="8" cy="9" r="1.5" />
              <path d="m4 18 6-6 4 4 3-3 4 4" />
            </svg>
          </Box>
          <Box component="span" sx={{ fontSize: 21, fontWeight: 550, letterSpacing: '-.025em' }}>Upload a furniture photo</Box>
          </>}
        </Button>
        <Box sx={{ mt: 2.5, minHeight: 52, display: 'grid', alignItems: 'center' }}>
          {photo ? <Button id="find-button" ref={findButton} variant="contained" disableElevation fullWidth disabled={loading || !validZip(zip)}
            onClick={search} sx={{ minHeight: 52, fontWeight: 600 }}
            startIcon={loading ? <CircularProgress size={19} color="inherit" aria-hidden="true"
              variant={reducedMotion ? 'determinate' : 'indeterminate'} value={75} /> : undefined}>
            {loading ? 'Finding similar items…' : 'Find similar items'}
          </Button> : <Typography component="p" color="text.secondary" sx={{ fontSize: 13 }}>
            or try an <Button id="example-button" onClick={useExample} sx={{ ...textButton, minWidth: 0, p: '6px 2px', fontSize: 'inherit' }}>example</Button>
          </Typography>}
        </Box>
        {uploadError && <Typography id="upload-error" role="alert" color="error" sx={{ mt: 2, fontSize: 13 }}>{uploadError}</Typography>}
      </Box>
    </Box>}

    {screen === 'results' && <Box component="section" aria-labelledby="results-title"
      sx={{ maxWidth: 1200, mx: 'auto', p: '44px 32px', '@media (max-width:620px)': { p: '28px 20px' } }}>
      <Box component="header" sx={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: 2.5, mb: '30px',
        '@media (max-width:620px)': { gap: 1.5, mb: 3 } }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, '@media (max-width:620px)': { gap: 1.5, flexBasis: '100%' } }}>
          <Photo photo={photo} compact />
          <Box>
            <Typography id="results-title" ref={resultsTitle} tabIndex={-1} component="h1" variant="h1"
              sx={{ outline: 'none', whiteSpace: 'nowrap' }}>Similar Items</Typography>
            <Typography color="text.secondary" sx={{ fontSize: 12, mt: .5 }}>Near {requestedZip}</Typography>
          </Box>
        </Box>
        <Button id="start-over" onClick={startOver}
          sx={{ ...textButton, whiteSpace: 'nowrap', ml: 'auto', alignSelf: 'flex-start',
            '@media (max-width:620px)': { order: -1 } }}>Search again</Button>
      </Box>
      <Box>
          <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 2,
            '@media (max-width:960px)': { gridTemplateColumns: 'repeat(2,minmax(0,1fr))' },
            '@media (max-width:620px)': { gap: '10px' } }}>
            {items.map(item => <ListingCard key={item[0]} item={item} />)}
          </Box>
          <Accordion variant="outlined" disableGutters expanded={explanationExpanded}
            onChange={(_, expanded) => setExplanationExpanded(expanded)}
            sx={{ mt: '25px', bgcolor: 'transparent', '&:before': { display: 'none' } }}>
            <AccordionSummary id="search-explanation" aria-controls="search-explanation-content"
              expandIcon={<span aria-hidden="true">⌄</span>} sx={{ fontSize: 12 }}>How this search worked</AccordionSummary>
            <AccordionDetails sx={{ p: { xs: 2, sm: 2.5 } }}>
              <SearchWalkthrough />
            </AccordionDetails>
          </Accordion>
      </Box>
    </Box>}
    <Box role="status" aria-live="polite" sx={{ position: 'absolute', width: '1px', height: '1px', m: '-1px', p: 0,
      overflow: 'hidden', clipPath: 'inset(50%)', whiteSpace: 'nowrap', border: 0 }}>{status}</Box>
  </Box>;
}

createRoot(document.getElementById('root')).render(<ThemeProvider theme={theme}><CssBaseline /><App /></ThemeProvider>);

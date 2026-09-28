import React from 'react';
import { Box, Button, CircularProgress, Typography, useMediaQuery } from '@mui/material';

export function searchSteps(includeVision = false) {
  return [
    { id: 'upload', label: 'Uploading photo' },
    { id: 'lens', label: 'Identifying furniture' },
    ...(includeVision ? [{ id: 'vision', label: 'Checking photo details' }] : []),
    { id: 'ebay', label: 'Searching eBay' },
    { id: 'filter', label: 'Checking matches' },
  ];
}

// Controlled by stage updates; timers exist only in the mockup's App.
export default function SearchLoading({ photo, steps = searchSteps(), activeStep, headingRef, onBack }) {
  const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  return <Box component="section" aria-labelledby="loading-title" sx={{ width: 'min(100%, 480px)' }}>
    <Box sx={{ width: 100, height: 100, mx: 'auto', mb: 3, borderRadius: '10px', overflow: 'hidden',
      border: 1, borderColor: 'divider' }}>{photo}</Box>
    <Typography id="loading-title" ref={headingRef} tabIndex={-1} component="h1" variant="h1"
      sx={{ textAlign: 'center', outline: 'none', mb: 4 }}>Finding similar items</Typography>
    <Box component="ol" aria-label="Search progress" sx={{ listStyle: 'none', p: 0, m: 0 }}>
      {steps.map((step, index) => {
        const current = index === activeStep;
        const complete = index < activeStep;
        return <Box component="li" key={step.id} aria-current={current ? 'step' : undefined}
          aria-label={`${step.label}: ${complete ? 'complete' : current ? 'in progress' : 'waiting'}`}
          sx={{ display: 'flex', alignItems: 'center', gap: 2, minHeight: 52,
            color: current || complete ? 'text.primary' : 'text.secondary' }}>
          <Box aria-hidden="true" sx={{ width: 26, height: 26, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
            {complete ? <Box component="span" sx={{ color: 'primary.main', fontSize: 22 }}>✓</Box>
              : current ? <CircularProgress size={22} thickness={4} aria-hidden="true"
                variant={reducedMotion ? 'determinate' : 'indeterminate'} value={75} />
                : <Box sx={{ width: 9, height: 9, border: 1, borderColor: 'divider', borderRadius: '50%' }} />}
          </Box>
          <Typography sx={{ fontSize: 15, fontWeight: current ? 600 : 400 }}>{step.label}</Typography>
        </Box>;
      })}
    </Box>
    <Button onClick={onBack} sx={{ mt: 3, textDecoration: 'underline', textUnderlineOffset: '3px' }}>Back</Button>
  </Box>;
}

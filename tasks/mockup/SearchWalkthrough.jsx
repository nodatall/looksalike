import React from 'react';
import { Box, Link, Typography } from '@mui/material';
import SearchFlowDiagram from './SearchFlowDiagram.jsx';

const phrase = 'victorian purple sofa';
const host = 'sfbay.craigslist.org';
const imageId = '<image_id>';
const listing = {
  title: 'Purple Victorian-style sofa',
  link: 'https://sfbay.craigslist.org/<area>/fuo/d/<listing>.html',
  thumbnail: '<thumbnail URL>',
};

function Payload({ title, value }) {
  return <Box sx={{ minWidth: 0 }}>
    <Typography component="h4" sx={{ fontSize: 11, fontWeight: 600, mb: .75 }}>{title}</Typography>
    <Box component="pre" sx={{ m: 0, p: 1.5, bgcolor: '#f0eee7', borderRadius: 1,
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', fontSize: 11, lineHeight: 1.65,
      whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
      {typeof value === 'string' ? value : JSON.stringify(value, null, 2)}
    </Box>
  </Box>;
}

function Stage({ label, title, children, request, response, docs }) {
  return <Box component="li" sx={{ listStyle: 'none', position: 'relative', pl: 2.5, pb: 3,
    borderLeft: '2px solid', borderColor: 'divider',
    '&:last-child': { pb: 0 },
    '&:before': { content: '""', position: 'absolute', top: 4, left: -5,
      width: 8, height: 8, borderRadius: '50%', bgcolor: 'primary.main' } }}>
    <Typography sx={{ fontSize: 11, color: 'primary.main', fontWeight: 600, mb: .5 }}>{label}</Typography>
    <Typography component="h3" sx={{ fontSize: 16, fontWeight: 600, mb: 1 }}>{title}</Typography>
    <Typography sx={{ fontSize: 12, color: 'text.secondary', lineHeight: 1.7 }}>{children}</Typography>
    {request && <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: 1.5, mt: 1.5,
      '@media (max-width:800px)': { gridTemplateColumns: '1fr' } }}>
      <Payload title="Request" value={request} />
      <Payload title="Response" value={response} />
    </Box>}
    {docs && <Link href={docs} target="_blank" rel="noreferrer" sx={{ display: 'inline-block', mt: 1, fontSize: 11 }}>
      API docs ↗
    </Link>}
  </Box>;
}

export default function SearchWalkthrough() {
  const lensRequest = {
    engine: 'google_lens', image_id: imageId,
    type: 'all',
    country: 'us', hl: 'en',
  };
  const lensResponse = { related_content: [{ query: phrase }, { query: 'antique velvet couch' }] };

  return <Box sx={{ color: 'text.primary' }}>
    <SearchFlowDiagram />
    <Box component="ol" aria-label="Search stages in order" sx={{ m: 0, p: 0, pl: .75 }}>
      <Stage label="Browser → Rails" title="Photo and ZIP received"
        request={'POST /searches\nContent-Type: multipart/form-data\n\nphoto: <compressed image>\nzip: "94103"'}
        response="Returned six listings.">
        Rails checked the resized photo before searching.
      </Stage>

      <Stage label="Local step · no API call" title="Search area selected">
        Selected {host} for ZIP 94103.
      </Stage>

      <Stage label="SerpApi call 1" title="Photo uploaded"
        request={'POST https://serpapi.com/image\nContent-Type: multipart/form-data\n\nimage: <compressed image>'}
        response={{ image_id: imageId }}
        docs="https://serpapi.com/image-api">
        SerpApi returned an image ID for the Lens call.
      </Stage>

      <Stage label="SerpApi call 2" title="Search terms found"
        request={`GET https://serpapi.com/search.json\n\nQuery parameters:\n${JSON.stringify(lensRequest, null, 2)}`}
        response={lensResponse}
        docs="https://serpapi.com/google-lens-api">
        Lens suggested search terms from the photo.
      </Stage>

      <Stage label="Local step · no API call" title="Query built">
        Used “{phrase}” and added “site:{host}”.
      </Stage>

      <Stage label="SerpApi call 3" title="Local listings found"
        request={`GET https://serpapi.com/search.json\n\nQuery parameters:\n${JSON.stringify({
          engine: 'google_images', q: `${phrase} site:${host}`,
          location: 'San Francisco, California, United States', gl: 'us', hl: 'en',
        }, null, 2)}`}
        response={{ images_results: [listing] }}
        docs="https://serpapi.com/google-images-api">
        Google Images returned listing links and photos.
      </Stage>

      <Stage label="Local step · no API call" title="Six listings selected">
        Kept local listings with titles and photos. Removed duplicates and ranked by matching words.
        <Box component="span" sx={{ display: 'block', mt: 1 }}>
          24 results → 14 local → 10 with titles and photos → 8 unique → 6 shown.
        </Box>
      </Stage>
    </Box>
  </Box>;
}

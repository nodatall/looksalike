import React from 'react';
import { Box } from '@mui/material';

const ink = '#171717';

function SketchBox({ x, y, width, height, children, dashed = false }) {
  return <g transform={`translate(${x} ${y})`}>
    <path d={`M 17 1 Q ${width / 2} -2 ${width - 18} 0
      Q ${width + 1} 0 ${width} 20 L ${width - 1} ${height - 18}
      Q ${width} ${height + 1} ${width - 20} ${height}
      Q ${width / 2} ${height - 2} 18 ${height + 1}
      Q -1 ${height} 0 ${height - 19} L 1 20 Q 0 0 17 1 Z`}
      fill="#fff" stroke={ink} strokeWidth="1.6" strokeDasharray={dashed ? '7 6' : undefined} />
    {children}
  </g>;
}

function Arrow({ from, to, y, label, response = false }) {
  return <g>
    <text x={(from + to) / 2} y={y - 12} textAnchor="middle" fontSize="18">{label}</text>
    <path d={`M ${from} ${y} Q ${(from + to) / 2} ${y + 2} ${to} ${y}`}
      fill="none" stroke={ink} strokeWidth="1.5" strokeDasharray={response ? '6 5' : undefined}
      markerEnd="url(#search-flow-arrow)" />
  </g>;
}

export default function SearchFlowDiagram() {
  return <Box component="figure" sx={{ m: 0, mb: 3, p: { xs: 1, sm: 2 },
    border: '1px solid #dedede', borderRadius: 1.5, bgcolor: '#fff' }}>
    <Box role="region" aria-label="Search flow diagram" tabIndex={0}
      sx={{ overflowX: 'auto', '&:focus-visible': { outline: '2px solid #171717', outlineOffset: 2 } }}>
      <Box component="svg" viewBox="0 0 1100 680" role="img"
        aria-labelledby="search-flow-title" aria-describedby="search-flow-description"
        sx={{ display: 'block', width: '100%', minWidth: 880, mx: 'auto', color: ink,
          fontFamily: '"Chalkboard SE", "Comic Sans MS", sans-serif', fontSize: 19 }}>
        <title id="search-flow-title">Photo search: browser, Rails, and SerpApi</title>
        <desc id="search-flow-description">
          The browser sends a photo and ZIP to Rails. Rails uses its local ZIP and Craigslist
          area files to choose a search area. SerpApi call 1 uploads the photo and returns an
          image ID. Call 2 sends that ID to Google Lens and returns search terms. Rails builds
          a query for the chosen Craigslist area. Call 3 searches Google Images and returns
          listing links and photos. Rails filters and ranks the results, then returns six
          listings to the browser. Solid arrows are requests; dashed arrows are responses.
        </desc>
        <defs>
          <marker id="search-flow-arrow" markerWidth="11" markerHeight="11" refX="9" refY="5"
            orient="auto-start-reverse" markerUnits="userSpaceOnUse">
            <path d="M 1 1 L 9 5 L 1 9" fill="none" stroke={ink} strokeWidth="1.5"
              strokeLinecap="round" strokeLinejoin="round" />
          </marker>
        </defs>

        <SketchBox x={22} y={217} width={168} height={165}>
          <text x="84" y="40" textAnchor="middle" fontSize="23">Browser</text>
          <path d="M 16 58 Q 84 60 150 58" stroke={ink} fill="none" />
          <text x="84" y="92" textAnchor="middle" fontSize="17">Upload a photo</text>
          <text x="84" y="119" textAnchor="middle" fontSize="17">Enter a ZIP</text>
          <text x="84" y="146" textAnchor="middle" fontSize="17">View results</text>
        </SketchBox>

        <SketchBox x={365} y={95} width={235} height={382}>
          <text x="117" y="43" textAnchor="middle" fontSize="25">Rails app</text>
          <path d="M 21 63 Q 117 65 214 62" stroke={ink} fill="none" />
          <text x="117" y="109" textAnchor="middle">Check photo + ZIP</text>
          <text x="117" y="172" textAnchor="middle">Choose search area</text>
          <text x="117" y="245" textAnchor="middle">Build query</text>
          <text x="117" y="329" textAnchor="middle">Filter + rank</text>
        </SketchBox>

        <SketchBox x={879} y={24} width={200} height={491} dashed>
          <text x="100" y="38" textAnchor="middle" fontSize="24">SerpApi</text>
        </SketchBox>
        {[
          { y: 91, title: 'Image upload', detail: 'POST /image' },
          { y: 236, title: 'Google Lens', detail: 'Identify the furniture' },
          { y: 381, title: 'Google Images', detail: 'Search Craigslist' },
        ].map(({ y, title, detail }) => <SketchBox key={title} x={895} y={y} width={168} height={110}>
          <text x="84" y="46" textAnchor="middle" fontSize="21">{title}</text>
          <text x="84" y="77" textAnchor="middle" fontSize="15">{detail}</text>
        </SketchBox>)}

        <Arrow from={193} to={362} y={272} label="Photo + ZIP" />
        <Arrow from={362} to={193} y={340} label="6 listings" response />
        <Arrow from={603} to={892} y={130} label="1. Photo" />
        <Arrow from={892} to={603} y={181} label="Image ID" response />
        <Arrow from={603} to={892} y={275} label="2. Image ID" />
        <Arrow from={892} to={603} y={326} label="Search terms" response />
        <Arrow from={603} to={892} y={420} label="3. Query + area" />
        <Arrow from={892} to={603} y={471} label="Listing links + photos" response />

        <path d="M 482 480 Q 484 507 482 538" stroke={ink} strokeWidth="1.5" fill="none"
          markerStart="url(#search-flow-arrow)" markerEnd="url(#search-flow-arrow)" />
        <text x="506" y="515" fontSize="17">Local lookup</text>
        <SketchBox x={365} y={543} width={235} height={116}>
          <text x="117" y="34" textAnchor="middle" fontSize="21">Local data files</text>
          <text x="117" y="67" textAnchor="middle" fontSize="17">ZIP coordinates</text>
          <text x="117" y="94" textAnchor="middle" fontSize="17">Craigslist areas</text>
        </SketchBox>

        <g fontSize="15">
          <path d="M 837 591 L 881 591" stroke={ink} strokeWidth="1.5" markerEnd="url(#search-flow-arrow)" />
          <text x="893" y="596">Request</text>
          <path d="M 837 621 L 881 621" stroke={ink} strokeWidth="1.5" strokeDasharray="6 5"
            markerEnd="url(#search-flow-arrow)" />
          <text x="893" y="626">Response</text>
        </g>
      </Box>
    </Box>
  </Box>;
}

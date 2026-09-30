import { useId } from "react";
import { Box } from "@mui/material";

function SketchBox({ x, y, width, height, dashed = false, children }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <path
        d={`M4 3 Q${width / 2} 0 ${width - 3} 3 L${width - 1} ${height - 3} Q${width / 2} ${height + 1} 3 ${height - 3} Z`}
        fill="white"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeDasharray={dashed ? "5 4" : undefined}
      />
      {children}
    </g>
  );
}
export default function SearchFlowDiagram({ stages = [] }) {
  const marker = useId().replace(/:/g, "");
  let call = 0;
  const services = [
    {
      stage: "upload",
      name: "SerpApi Image",
      detail: "POST /image",
      input: "photo",
      output: "reference",
    },
    {
      stage: "lens",
      name: "Google Lens",
      detail: "via SerpApi",
      input: "reference",
      output: "titles + phrase",
    },
    {
      stage: "vision",
      name: "Venice (optional)",
      detail: "photo description",
      input: "photo, if needed",
      output: "description",
    },
    {
      stage: "ebay",
      name: "eBay search",
      detail: "via SerpApi",
      input: "phrase",
      output: "listings",
    },
  ];
  return (
    <Box
      component="figure"
      sx={{
        m: 0,
        mb: 3,
        p: 1.5,
        bgcolor: "#fff",
        color: "#111",
        border: "1px solid #ddd",
        borderRadius: 2,
      }}
    >
      <Box
        role="region"
        aria-label="Search flow diagram"
        tabIndex={0}
        sx={{ overflowX: "auto", "&:focus-visible": { outline: "2px solid #111" } }}
      >
        <svg
          viewBox="0 0 1100 570"
          role="img"
          aria-labelledby={`${marker}-title`}
          style={{
            display: "block",
            width: "100%",
            minWidth: 750,
            fontFamily: '"Chalkboard SE", "Comic Sans MS", sans-serif',
          }}
        >
          <title id={`${marker}-title`}>
            The browser sends a photo to Rails. Rails calls Image upload, Lens, optional Venice and
            eBay, then checks the listings locally. Solid arrows are requests and dashed arrows are
            responses. Only dispatched external calls are numbered.
          </title>
          <defs>
            <marker id={marker} markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">
              <path d="m1 1 6 3-6 3" fill="none" stroke="currentColor" />
            </marker>
          </defs>
          <SketchBox x={15} y={210} width={160} height={125}>
            <text x="80" y="47" textAnchor="middle" fontSize="23">
              Browser
            </text>
            <text x="80" y="84" textAnchor="middle" fontSize="16">
              Choose a photo
            </text>
          </SketchBox>
          <SketchBox x={340} y={12} width={225} height={500}>
            <text x="112" y="45" textAnchor="middle" fontSize="25">
              Rails
            </text>
            <path d="M20 62 L205 62" stroke="currentColor" />
            <text x="112" y="100" textAnchor="middle" fontSize="17">
              Validate photo
            </text>
            <text x="112" y="220" textAnchor="middle" fontSize="17">
              Coordinate calls
            </text>
            <path d="M20 362 L205 362" stroke="currentColor" />
            <text x="112" y="400" textAnchor="middle" fontSize="19">
              Local filtering
            </text>
            <text x="112" y="433" textAnchor="middle" fontSize="14">
              US location + title checks
            </text>
            <text x="112" y="468" textAnchor="middle" fontSize="14">
              Return up to six listings
            </text>
          </SketchBox>
          <text x="255" y="232" textAnchor="middle" fontSize="16">
            Photo
          </text>
          <path d="M177 249 L337 249" stroke="currentColor" markerEnd={`url(#${marker})`} />
          <text x="255" y="298" textAnchor="middle" fontSize="16">
            Results
          </text>
          <path
            d="M337 315 L177 315"
            stroke="currentColor"
            strokeDasharray="5 4"
            markerEnd={`url(#${marker})`}
          />
          {services.map((service, index) => {
            const y = index * 126 + 18;
            const dispatched = stages.some(
              (entry) => entry.stage === service.stage && entry.status !== "skipped",
            );
            const prefix = dispatched ? `${++call}. ` : "";
            return (
              <g key={service.stage}>
                <SketchBox
                  x={840}
                  y={y}
                  width={245}
                  height={100}
                  dashed={service.stage === "vision"}
                >
                  <text x="122" y="39" textAnchor="middle" fontSize="21">
                    {service.name}
                  </text>
                  <text x="122" y="72" textAnchor="middle" fontSize="16">
                    {service.detail}
                  </text>
                </SketchBox>
                <text x="700" y={y + 21} textAnchor="middle" fontSize="16">
                  {prefix}
                  {service.input}
                </text>
                <path
                  d={`M568 ${y + 36} L837 ${y + 36}`}
                  stroke="currentColor"
                  markerEnd={`url(#${marker})`}
                />
                <text x="700" y={y + 66} textAnchor="middle" fontSize="16">
                  {service.output}
                </text>
                <path
                  d={`M837 ${y + 83} L568 ${y + 83}`}
                  stroke="currentColor"
                  strokeDasharray="5 4"
                  markerEnd={`url(#${marker})`}
                />
              </g>
            );
          })}
          <text x="340" y="550" fontSize="15">
            Solid: request → Dashed: response ← Local filtering makes no provider call.
          </text>
        </svg>
      </Box>
    </Box>
  );
}

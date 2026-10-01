import { Box, Typography } from "@mui/material";
import SearchFlowDiagram from "./SearchFlowDiagram";

const labels = {
  upload: "Upload the photo",
  lens: "Identify the furniture with Lens",
  vision: "Describe the photo with Venice",
  ebay: "Search eBay",
  filter: "Check the listings locally",
};
function excerpts(titles) {
  return titles
    ?.slice(0, 2)
    .map((title) => `“${title.length > 110 ? `${title.slice(0, 107)}…` : title}”`)
    .join("; ");
}
function stageDetails(stage, preparation) {
  const p = stage.request?.parameters || {};
  const s = stage.summary || {};
  const rows = [];
  if (stage.stage === "upload") {
    if (p.format)
      rows.push(`JPEG${p.bytes !== undefined ? ` · ${(p.bytes / 1000).toFixed(0)} kB` : ""}`);
    if (s.photo_reference_received) rows.push("Photo reference received; its value is omitted.");
  } else if (stage.stage === "lens") {
    const parameters = [
      p.engine,
      p.type ? `type=${p.type}` : null,
      p.country ? `country=${p.country}` : null,
      p.hl ? `language=${p.hl}` : null,
    ].filter(Boolean);
    if (parameters.length) rows.push(parameters.join(" · "));
    if (s.visual_matches !== undefined) rows.push(`${s.visual_matches} visual matches returned.`);
    rows.push(`Lens phrase: ${s.query || preparation?.lens_query || "No usable phrase recorded"}.`);
    if (s.titles?.length) rows.push(`Title excerpts: ${excerpts(s.titles)}`);
  } else if (stage.stage === "vision") {
    const model = p.model || s.model;
    if (model) rows.push(`Model: ${model}`);
    const reason = s.fallback_reason || s.reason;
    if (reason) rows.push(`Reason: ${reason.replaceAll("_", " ")}`);
    if (stage.status !== "skipped") rows.push(`Venice phrase: ${s.query || "No phrase returned"}.`);
  } else if (stage.stage === "ebay") {
    if (p._nkw) rows.push(`Phrase: ${p._nkw}`);
    if (p.ebay_domain)
      rows.push(`Marketplace: ${p.ebay_domain}${p._ipg ? ` · requested page size ${p._ipg}` : ""}`);
    if (s.returned !== undefined) rows.push(`${s.returned} listings returned.`);
    if (s.titles?.length) rows.push(`Title excerpts: ${excerpts(s.titles)}`);
  } else if (stage.stage === "filter") {
    const counts = ["returned", "eligible", "accepted", "displayed"]
      .filter((key) => s[key] !== undefined)
      .map((key) => `${key[0].toUpperCase()}${key.slice(1)} ${s[key]}`);
    if (counts.length) rows.push(counts.join(" · "));
    const rejected = [
      "invalid_url",
      "missing_metadata",
      "not_explicit_us",
      "duplicate",
      "title_rejected",
    ]
      .filter((key) => s[key] > 0)
      .map((key) => `${key.replaceAll("_", " ")}: ${s[key]}`);
    if (rejected.length) rows.push(`Rejected: ${rejected.join(" · ")}`);
    const reasons = Object.entries(s.title_rejection_reasons || {})
      .filter(([, count]) => count > 0)
      .map(([reason, count]) => `${reason.replaceAll("_", " ")}: ${count}`);
    if (reasons.length) rows.push(`Title checks: ${reasons.join(" · ")}`);
  }
  if (s.note) rows.push(s.note);
  if (!rows.length)
    rows.push(
      stage.status === "failed"
        ? "No response details were recorded."
        : "Details were not recorded.",
    );
  return rows;
}
function CallCounts({ label, counts }) {
  if (!counts) return null;
  return (
    <Typography sx={{ fontSize: 13, mb: 1 }}>
      {label}: {counts.uploads} image uploads, {counts.serpapi} SerpApi searches, {counts.vision}{" "}
      Venice attempts.
    </Typography>
  );
}
export default function SearchWalkthrough({ result, restored = false }) {
  let call = 0;
  const saved = restored || ["cache", "snapshot"].includes(result.source);
  const stages = result.stages || [];
  return (
    <Box>
      <SearchFlowDiagram stages={stages} />
      <CallCounts
        label={saved ? "New calls for this view" : "Calls for this search"}
        counts={saved ? { uploads: 0, serpapi: 0, vision: 0 } : result.attempts}
      />
      {saved && <CallCounts label="Original search" counts={result.original_attempts} />}
      {result.retrieved_at && (
        <Typography sx={{ fontSize: 12, mb: 3 }} color="text.secondary">
          Retrieved {new Date(result.retrieved_at).toUTCString()}.
        </Typography>
      )}
      <Box sx={{ mb: 3, mt: 3 }}>
        <Typography sx={{ fontWeight: 600, fontSize: 15 }}>Browser → Rails</Typography>
        <Typography sx={{ fontSize: 13 }}>
          {result.source === "snapshot"
            ? "Recorded experiment replayed locally; no photo sent."
            : restored
              ? "Completed result restored in this tab; no photo sent again."
              : result.source === "cache"
                ? "Reduced JPEG sent to POST /searches; Rails returned its cached result."
                : "Reduced JPEG sent to POST /searches."}
        </Typography>
      </Box>
      {stages.map((stage) => {
        const external =
          ["upload", "lens", "vision", "ebay"].includes(stage.stage) && stage.status !== "skipped";
        return (
          <Box key={stage.stage} sx={{ mb: 3, pb: 2, borderBottom: 1, borderColor: "divider" }}>
            <Typography component="h3" sx={{ fontSize: 15, fontWeight: 600, mb: 1 }}>
              {external ? `${++call}. ` : ""}
              {labels[stage.stage]}{" "}
              <Box component="span" sx={{ fontSize: 12, fontWeight: 400 }}>
                · {stage.status}
                {stage.duration_ms !== undefined
                  ? ` · ${(stage.duration_ms / 1000).toFixed(2)}s`
                  : ""}
              </Box>
            </Typography>
            {stage.request?.endpoint && (
              <Typography sx={{ fontSize: 12, color: "text.secondary", mb: 0.5 }}>
                {stage.request.provider} · {stage.request.endpoint}
              </Typography>
            )}
            {stageDetails(stage, result.query_preparation).map((row) => (
              <Typography key={row} sx={{ fontSize: 13, mb: 0.6, overflowWrap: "anywhere" }}>
                {row}
              </Typography>
            ))}
          </Box>
        );
      })}
    </Box>
  );
}

import { Box, Typography } from "@mui/material";
import { supportingLensTitles } from "./lensTitleEvidence";

const labels = {
  upload: "Upload the photo",
  lens: "Identify the furniture with Lens",
  vision: "Fallback LLM description",
  ebay: "Search eBay",
  filter: "Check the listings locally",
};
const visionReasons = {
  missing_phrase: "Lens did not provide a usable search phrase, so the LLM examined the photo.",
  bare_category:
    "Lens identified only the furniture type, so the LLM examined the photo for more detail.",
  no_concrete_trait:
    "Lens's search phrase had no recognized color or material, so the LLM examined the photo for more detail.",
  lens_has_concrete_trait: "Lens found a usable color or material, so the LLM was not needed.",
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
  } else if (stage.stage === "lens") {
    const parameters = [
      p.engine,
      p.type ? `type=${p.type}` : null,
      p.country ? `country=${p.country}` : null,
      p.hl ? `language=${p.hl}` : null,
    ].filter(Boolean);
    if (parameters.length) rows.push(parameters.join(" · "));
    if (s.visual_matches !== undefined) rows.push(`${s.visual_matches} visual matches returned.`);
    const query = s.query || preparation?.lens_query;
    rows.push(`Lens phrase: ${query || "No usable phrase recorded"}.`);
    const titles = supportingLensTitles({
      titles: s.titles,
      query,
      category: s.category || preparation?.lens_category,
    });
    if (titles.length) rows.push(`Supporting titles: ${excerpts(titles)}`);
  } else if (stage.stage === "vision") {
    const model = p.model || s.model;
    if (model) rows.push(`Model: ${model}`);
    const reason = s.fallback_reason || s.reason;
    if (reason)
      rows.push(
        visionReasons[reason] ||
          (stage.status === "skipped"
            ? "The LLM was not needed for this search."
            : "The LLM examined the photo for more detail."),
      );
    if (stage.status !== "skipped")
      rows.push(`LLM description: ${s.query || "No usable description returned"}.`);
  } else if (stage.stage === "ebay") {
    if (p._nkw) rows.push(`Phrase: ${p._nkw}`);
    if (p.ebay_domain)
      rows.push(`Marketplace: ${p.ebay_domain}${p._ipg ? ` · requested page size ${p._ipg}` : ""}`);
    if (s.returned !== undefined) rows.push(`${s.returned} listings returned.`);
  } else if (stage.stage === "filter") {
    const counts = ["returned", "eligible", "accepted", "displayed"]
      .filter((key) => s[key] !== undefined)
      .map((key) => `${key[0].toUpperCase()}${key.slice(1)} ${s[key]}`);
    if (counts.length) {
      rows.push(counts.join(" · "));
      rows.push(
        "Eligible listings have a valid eBay item link, title, image, explicit U.S. location, and unique item ID; accepted listings also pass a title check that removes accessories, parts, miniatures, and mismatched furniture types.",
      );
    }
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
function CallCounts({ counts }) {
  if (!counts) return null;
  return (
    <Typography sx={{ fontSize: 13, mb: 1 }}>
      {counts.uploads} image uploads, {counts.serpapi} SerpApi searches, {counts.vision} LLM
      attempts.
    </Typography>
  );
}
export default function SearchWalkthrough({ result, restored = false }) {
  let call = 0;
  const stages = result.stages || [];
  return (
    <Box>
      <CallCounts counts={result.original_attempts || result.attempts} />
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

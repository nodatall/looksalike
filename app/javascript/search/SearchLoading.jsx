import { Box, Button, CircularProgress, Typography, useMediaQuery } from "@mui/material";

export const STAGE_LABELS = {
  upload: "Uploading photo",
  lens: "Identifying furniture",
  vision: "Checking photo details",
  ebay: "Searching eBay",
  filter: "Checking matches",
};
export default function SearchLoading({ photo, events, headingRef, onBack }) {
  const reducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
  const steps = ["upload", "lens", ...(events.vision ? ["vision"] : []), "ebay", "filter"];
  const current = steps.find((stage) => events[stage]?.status === "started");
  return (
    <Box component="section" aria-labelledby="loading-title" sx={{ width: "min(100%, 480px)" }}>
      <Box
        component="img"
        src={photo}
        alt="Selected furniture"
        sx={{
          display: "block",
          width: 110,
          height: 110,
          objectFit: "contain",
          mx: "auto",
          mb: 3,
          borderRadius: 2,
        }}
      />
      <Typography
        id="loading-title"
        ref={headingRef}
        tabIndex={-1}
        component="h1"
        variant="h1"
        sx={{ textAlign: "center", outline: "none", mb: 4 }}
      >
        Finding similar items
      </Typography>
      <Box
        role="status"
        aria-live="polite"
        aria-atomic="true"
        sx={{
          position: "absolute",
          width: 1,
          height: 1,
          overflow: "hidden",
          clipPath: "inset(50%)",
        }}
      >
        {current ? STAGE_LABELS[current] : "Waiting for search response"}
      </Box>
      <Box component="ol" aria-label="Search progress" sx={{ listStyle: "none", p: 0, m: 0 }}>
        {steps.map((stage) => {
          const event = events[stage];
          const running = event?.status === "started";
          const complete = event?.status === "complete";
          const failed = event?.status === "failed";
          return (
            <Box
              component="li"
              key={stage}
              aria-current={running ? "step" : undefined}
              sx={{
                display: "flex",
                gap: 2,
                alignItems: "center",
                minHeight: 54,
                color: event ? "text.primary" : "text.secondary",
              }}
            >
              <Box
                aria-hidden="true"
                sx={{ width: 26, display: "grid", placeItems: "center", flexShrink: 0 }}
              >
                {complete ? (
                  "✓"
                ) : failed ? (
                  "×"
                ) : running ? (
                  <CircularProgress
                    size={22}
                    variant={reducedMotion ? "determinate" : "indeterminate"}
                    value={75}
                  />
                ) : (
                  "○"
                )}
              </Box>
              <Typography sx={{ fontSize: 15, fontWeight: running ? 600 : 400 }}>
                {STAGE_LABELS[stage]}
                {failed ? " — failed" : ""}
                {complete && event.duration_ms !== undefined
                  ? ` · ${(event.duration_ms / 1000).toFixed(1)}s`
                  : ""}
                <Box
                  component="span"
                  sx={{
                    position: "absolute",
                    width: 1,
                    height: 1,
                    overflow: "hidden",
                    clipPath: "inset(50%)",
                  }}
                >
                  {complete
                    ? " complete"
                    : running
                      ? " in progress"
                      : failed
                        ? " failed"
                        : " waiting"}
                </Box>
              </Typography>
            </Box>
          );
        })}
      </Box>
      <Button onClick={onBack} sx={{ mt: 3, textDecoration: "underline" }}>
        Back
      </Button>
    </Box>
  );
}

import { useState } from "react";
import { Box, Button, TextField, Typography } from "@mui/material";

export default function SearchApp() {
  const [zip, setZip] = useState("");

  return (
    <Box component="main">
      <Box
        component="section"
        aria-label="Choose a furniture photo"
        sx={{
          minHeight: "100svh",
          display: "grid",
          placeItems: "center",
          px: 3,
          py: 5,
          "@media (max-width:620px)": { px: "22px", py: "70px" },
        }}
      >
        <Box sx={{ width: "min(100%, 520px)", textAlign: "center" }}>
          <Typography component="h1" variant="h1" sx={{ mb: 3.5, textWrap: "balance" }}>
            Find similar items on Craigslist near you
          </Typography>
          <Box sx={{ mb: 3 }}>
            <TextField
              id="zip-code"
              label="ZIP code"
              name="zip"
              type="text"
              required
              fullWidth
              variant="outlined"
              placeholder="e.g. 10001"
              value={zip}
              onChange={(event) => setZip(event.target.value)}
              slotProps={{
                inputLabel: { required: false },
                htmlInput: {
                  inputMode: "numeric",
                  autoComplete: "postal-code",
                  maxLength: 5,
                  pattern: "[0-9]{5}",
                },
              }}
              sx={{
                textAlign: "left",
                "& .MuiOutlinedInput-root": { bgcolor: "background.paper" },
              }}
            />
          </Box>
          <Button
            id="drop-zone"
            variant="outlined"
            fullWidth
            disabled
            aria-label="Upload a furniture photo, currently unavailable"
            sx={{
              height: 310,
              p: "48px 24px",
              borderStyle: "dashed",
              borderColor: "#9daa92",
              borderRadius: "14px",
              bgcolor: "rgba(255,255,255,.35)",
              color: "text.primary",
              display: "flex",
              flexDirection: "column",
              gap: "18px",
              overflow: "hidden",
              "&.Mui-disabled": {
                borderStyle: "dashed",
                borderColor: "#9daa92",
                color: "text.primary",
              },
              "@media (max-width:620px)": { height: 280 },
            }}
          >
            <Box
              component="span"
              aria-hidden="true"
              sx={{
                width: 58,
                height: 58,
                display: "grid",
                placeItems: "center",
                color: "primary.main",
                borderRadius: "50%",
                bgcolor: "#e6ebde",
              }}
            >
              <svg
                aria-hidden="true"
                width="28"
                height="28"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              >
                <rect x="3" y="4" width="18" height="16" rx="3" />
                <circle cx="8" cy="9" r="1.5" />
                <path d="m4 18 6-6 4 4 3-3 4 4" />
              </svg>
            </Box>
            <Box component="span" sx={{ fontSize: 21, fontWeight: 550, letterSpacing: "-.025em" }}>
              Upload a furniture photo
            </Box>
          </Button>
          <Box sx={{ mt: 2.5, minHeight: 52, display: "grid", alignItems: "center" }}>
            <Typography component="p" color="text.secondary" sx={{ fontSize: 13 }}>
              or try an{" "}
              <Button
                id="example-button"
                disabled
                aria-label="Example, currently unavailable"
                sx={{
                  textDecoration: "underline",
                  textUnderlineOffset: "3px",
                  minWidth: 0,
                  p: "6px 2px",
                  fontSize: "inherit",
                  "&.Mui-disabled": { color: "primary.main" },
                }}
              >
                example
              </Button>
            </Typography>
          </Box>
        </Box>
      </Box>
    </Box>
  );
}

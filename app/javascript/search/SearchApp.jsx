import { useEffect, useRef, useState } from "react";
import { PhotoError, preparePhoto } from "./preparePhoto";
import { Box, Button, CircularProgress, TextField, Typography } from "@mui/material";

export default function SearchApp() {
  const [zip, setZip] = useState("");
  const [photo, setPhoto] = useState(null);
  const [error, setError] = useState("");
  const [preparing, setPreparing] = useState(false);
  const [dragging, setDragging] = useState(false);
  const input = useRef(null);
  const pending = useRef(null);
  const previewUrl = useRef(null);

  useEffect(
    () => () => {
      pending.current?.abort();
      if (previewUrl.current) URL.revokeObjectURL(previewUrl.current);
    },
    [],
  );

  async function selectPhoto(file) {
    pending.current?.abort();
    const controller = new AbortController();
    pending.current = controller;
    setError("");
    setPreparing(true);
    try {
      const prepared = await preparePhoto(file, { signal: controller.signal });
      controller.signal.throwIfAborted();
      const url = URL.createObjectURL(prepared.blob);
      if (previewUrl.current) URL.revokeObjectURL(previewUrl.current);
      previewUrl.current = url;
      setPhoto({ ...prepared, url });
    } catch (failure) {
      if (!controller.signal.aborted)
        setError(
          failure instanceof PhotoError
            ? failure.message
            : "This photo could not be read. Choose another photo.",
        );
    } finally {
      if (!controller.signal.aborted) setPreparing(false);
    }
  }

  return (
    <Box component="main">
      <input
        ref={input}
        id="photo-input"
        type="file"
        accept="image/jpeg,image/png,image/webp"
        hidden
        onChange={(event) => {
          const file = event.target.files[0];
          event.target.value = "";
          if (file) selectPhoto(file);
        }}
      />
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
            aria-label={photo ? "Choose another furniture photo" : "Upload a furniture photo"}
            aria-describedby={error ? "upload-error" : undefined}
            aria-busy={preparing}
            onClick={() => input.current?.click()}
            onDragOver={(event) => {
              event.preventDefault();
              setDragging(true);
            }}
            onDragLeave={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget)) setDragging(false);
            }}
            onDrop={(event) => {
              event.preventDefault();
              setDragging(false);
              if (event.dataTransfer.files.length !== 1) {
                pending.current?.abort();
                setPreparing(false);
                setError("Choose one furniture photo at a time.");
                return;
              }
              selectPhoto(event.dataTransfer.files[0]);
            }}
            sx={{
              height: 310,
              p: photo ? 0 : "48px 24px",
              borderStyle: "dashed",
              borderColor: "#9daa92",
              borderRadius: "14px",
              bgcolor: dragging ? "#e6ebde" : "rgba(255,255,255,.35)",
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
            {photo ? (
              <Box
                component="img"
                src={photo.url}
                alt="Selected furniture photo"
                sx={{ display: "block", width: "100%", height: "100%", objectFit: "contain" }}
              />
            ) : (
              <>
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
                <Box
                  component="span"
                  sx={{ fontSize: 21, fontWeight: 550, letterSpacing: "-.025em" }}
                >
                  Upload a furniture photo
                </Box>
              </>
            )}
          </Button>
          <Box sx={{ mt: 2.5, minHeight: 52, display: "grid", alignItems: "center" }}>
            {photo ? (
              <Button
                id="find-button"
                variant="contained"
                disableElevation
                fullWidth
                disabled
                sx={{ minHeight: 52, fontWeight: 600 }}
              >
                Find similar items
              </Button>
            ) : (
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
            )}
          </Box>
          {preparing && (
            <Box
              role="status"
              sx={{
                mt: 1,
                display: "flex",
                justifyContent: "center",
                gap: 1,
                alignItems: "center",
              }}
            >
              <CircularProgress size={16} aria-hidden="true" />
              <Typography sx={{ fontSize: 13 }}>Preparing photo…</Typography>
            </Box>
          )}
          {error && (
            <Typography id="upload-error" role="alert" color="error" sx={{ mt: 2, fontSize: 13 }}>
              {error}
            </Typography>
          )}
        </Box>
      </Box>
    </Box>
  );
}

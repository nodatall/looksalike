import { useEffect, useRef, useState } from "react";
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Box,
  Button,
  CircularProgress,
  IconButton,
  Typography,
} from "@mui/material";
import { PhotoError, preparePhoto } from "./preparePhoto";
import {
  clearSavedView,
  readSavedView,
  referenceThumbnail,
  saveView,
  validateCompletedResult,
} from "./searchState";
import { submitPhoto } from "./searchProtocol";
import SearchLoading from "./SearchLoading";
import SearchResults from "./SearchResults";
import SearchWalkthrough from "./SearchWalkthrough";
import examplePhoto from "./assets/modern-sofa.jpg";

function sessionStore() {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}
export default function SearchApp({ search = submitPhoto, preview = false }) {
  const [initial] = useState(() => readSavedView(sessionStore(), { preview }));
  const [screen, setScreen] = useState(initial ? "results" : "upload");
  const [view, setView] = useState(initial);
  const [restored, setRestored] = useState(Boolean(initial));
  const [photo, setPhoto] = useState(null);
  const [error, setError] = useState("");
  const [failure, setFailure] = useState(null);
  const [preparing, setPreparing] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [events, setEvents] = useState({});
  const [storageAvailable, setStorageAvailable] = useState(true);
  const input = useRef(null);
  const dropZone = useRef(null);
  const heading = useRef(null);
  const preparation = useRef(null);
  const request = useRef(null);
  const previewUrl = useRef(null);
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    const cancel = () => {
      preparation.current?.abort();
      request.current?.abort();
    };
    window.addEventListener("pagehide", cancel);
    return () => {
      mounted.current = false;
      cancel();
      window.removeEventListener("pagehide", cancel);
      if (previewUrl.current) URL.revokeObjectURL(previewUrl.current);
    };
  }, []);
  useEffect(() => {
    heading.current?.focus({ preventScroll: screen === "upload" && !error });
  }, [screen, error]);

  function releasePreview() {
    if (previewUrl.current) URL.revokeObjectURL(previewUrl.current);
    previewUrl.current = null;
  }
  function back() {
    request.current?.abort();
    request.current = null;
    setScreen("upload");
    setError("");
    setFailure(null);
  }
  function again() {
    back();
    preparation.current?.abort();
    preparation.current = null;
    releasePreview();
    clearSavedView(sessionStore(), { preview });
    setPhoto(null);
    setView(null);
    setRestored(false);
    setPreparing(false);
    setStorageAvailable(true);
  }
  function clearPhoto() {
    again();
    setDragging(false);
    if (input.current) input.current.value = "";
    dropZone.current?.focus();
  }
  async function selectPhoto(files, example = false) {
    if (request.current) return;
    preparation.current?.abort();
    if (typeof files !== "function" && files.length !== 1) {
      setPreparing(false);
      setError("Choose one furniture photo at a time.");
      return;
    }
    const controller = new AbortController();
    preparation.current = controller;
    setError("");
    setFailure(null);
    setPreparing(true);
    // Replacement invalidates the previous prepared photo immediately.
    releasePreview();
    setPhoto(null);
    try {
      const selected = typeof files === "function" ? await files(controller.signal) : files[0];
      controller.signal.throwIfAborted();
      const prepared = await preparePhoto(selected, { signal: controller.signal });
      const reference = await referenceThumbnail(prepared.blob, controller.signal);
      controller.signal.throwIfAborted();
      if (!mounted.current || preparation.current !== controller) return;
      const url = URL.createObjectURL(prepared.blob);
      previewUrl.current = url;
      setPhoto({ ...prepared, url, reference, example });
    } catch (failure) {
      if (!controller.signal.aborted && mounted.current)
        setError(
          failure instanceof PhotoError
            ? failure.message
            : "This photo could not be read. Choose another photo.",
        );
    } finally {
      if (preparation.current === controller && mounted.current) {
        preparation.current = null;
        setPreparing(false);
      }
    }
  }
  async function chooseExample() {
    // Embedded licensed reference: this fetch cannot contact an external provider.
    await selectPhoto(async (signal) => {
      const response = await fetch(examplePhoto, { signal });
      return response.blob();
    }, true);
  }
  function complete(result, selected) {
    const safe = validateCompletedResult(result, { preview });
    if (!safe) throw new Error("The search returned an unreadable result. Please try again later.");
    const completed = {
      result: safe,
      reference: selected.reference,
      explanationOpen: false,
      page: 0,
    };
    setView(completed);
    setRestored(false);
    setStorageAvailable(saveView(sessionStore(), completed, { preview }));
    setScreen("results");
    releasePreview();
    setPhoto(null);
  }
  async function find() {
    if (!photo || preparing || request.current) return;
    const selected = photo;
    setError("");
    setFailure(null);
    clearSavedView(sessionStore(), { preview });
    const controller = new AbortController();
    request.current = controller;
    const timeout = setTimeout(
      () => controller.abort(new Error("The search took too long. Please try again.")),
      65_000,
    );
    setEvents({});
    setScreen("loading");
    try {
      const result = await search(selected.blob, {
        signal: controller.signal,
        example: selected.example,
        csrfToken: document.querySelector('meta[name="csrf-token"]')?.content,
        onStage: (event) => {
          if (mounted.current && request.current === controller && !controller.signal.aborted)
            setEvents((current) => ({ ...current, [event.stage]: event }));
        },
      });
      controller.signal.throwIfAborted();
      if (!mounted.current || request.current !== controller) return;
      if (!["success", "empty"].includes(result.status)) {
        setFailure(result);
        throw new Error(result.message || "The search could not finish. Please try again.");
      }
      complete(result, selected);
    } catch (failure) {
      if (mounted.current && request.current === controller) {
        setScreen("upload");
        setError(failure.message || "The search could not finish. Please try again.");
      }
    } finally {
      clearTimeout(timeout);
      if (request.current === controller) request.current = null;
    }
  }
  function toggleExplanation(open) {
    const updated = { ...view, explanationOpen: open };
    setView(updated);
    setStorageAvailable(saveView(sessionStore(), updated, { preview }));
  }
  function changePage(page) {
    const updated = { ...view, page };
    setView(updated);
    setStorageAvailable(saveView(sessionStore(), updated, { preview }));
  }
  return (
    <Box component="main" sx={{ minHeight: "100svh", minWidth: 0, px: { xs: 2, sm: 3 } }}>
      <input
        ref={input}
        id="photo-input"
        type="file"
        accept="image/jpeg,image/png,image/webp"
        hidden
        onChange={(event) => {
          const files = Array.from(event.target.files);
          event.target.value = "";
          if (files.length) void selectPhoto(files);
        }}
      />
      {screen === "results" && view ? (
        <SearchResults
          {...view}
          restored={restored}
          storageAvailable={storageAvailable}
          headingRef={heading}
          onAgain={again}
          onExplanationChange={toggleExplanation}
          onPageChange={changePage}
        />
      ) : (
        <Box
          sx={{
            minHeight: "100svh",
            minWidth: 0,
            display: "grid",
            gridTemplateColumns: "minmax(0, 1fr)",
            placeItems: "center",
            py: 5,
          }}
        >
          {screen === "loading" ? (
            <SearchLoading photo={photo?.url} events={events} headingRef={heading} onBack={back} />
          ) : (
            <Box
              component="section"
              aria-label="Choose a furniture photo"
              sx={{ width: "min(100%, 520px)", minWidth: 0, maxWidth: "100%", textAlign: "center" }}
            >
              <Typography
                ref={heading}
                tabIndex={-1}
                component="h1"
                variant="h1"
                sx={{ mb: 3.5, textWrap: "balance", outline: "none" }}
              >
                Find similar furniture on eBay.
              </Typography>
              <Box
                sx={{
                  position: "relative",
                  "&:hover #clear-photo-button, &:focus-within #clear-photo-button": {
                    opacity: 1,
                  },
                }}
              >
                <Button
                  ref={dropZone}
                  id="drop-zone"
                  variant="outlined"
                  disableRipple
                  fullWidth
                  aria-label={photo ? "Replace furniture photo" : "Upload a furniture photo"}
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
                    void selectPhoto(Array.from(event.dataTransfer.files));
                  }}
                  sx={{
                    height: { xs: 280, sm: 310 },
                    p: photo ? 0 : 3,
                    borderStyle: "dashed",
                    borderColor: "#9daa92",
                    borderRadius: "6px",
                    bgcolor: dragging ? "#e6ebde" : "rgba(255,255,255,.35)",
                    color: "text.primary",
                    display: "flex",
                    flexDirection: "column",
                    gap: 2,
                    overflow: "hidden",
                    "&.Mui-focusVisible": {
                      outline: "2px solid",
                      outlineColor: "primary.main",
                      outlineOffset: 3,
                    },
                  }}
                >
                  {photo ? (
                    <Box
                      component="img"
                      src={photo.url}
                      alt="Selected furniture photo; click to replace"
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
                {(photo || preparing) && (
                  <IconButton
                    id="clear-photo-button"
                    aria-label="Clear photo"
                    disableRipple
                    onClick={clearPhoto}
                    sx={{
                      position: "absolute",
                      top: 2,
                      right: 2,
                      width: 40,
                      height: 40,
                      color: "text.primary",
                      transition: "opacity 200ms ease-in-out",
                      "&:hover": { bgcolor: "transparent" },
                      "&.Mui-focusVisible": {
                        outline: "2px solid",
                        outlineColor: "primary.main",
                        outlineOffset: 2,
                      },
                      "@media (hover: hover) and (pointer: fine)": { opacity: 0 },
                      "@media (prefers-reduced-motion: reduce)": { transition: "none" },
                    }}
                  >
                    <Box
                      component="span"
                      aria-hidden="true"
                      sx={{ fontSize: 25, lineHeight: 1, opacity: 0.7 }}
                    >
                      ×
                    </Box>
                  </IconButton>
                )}
              </Box>
              <Box sx={{ minHeight: 112, display: "flow-root" }}>
                {preparing && (
                  <Box
                    role="status"
                    sx={{
                      mt: 2,
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
                {(photo || preparing) && (
                  <Button
                    id="find-button"
                    variant="outlined"
                    disableElevation
                    disabled={!photo || preparing}
                    onClick={find}
                    sx={{
                      mt: 2.5,
                      px: 2.5,
                      minHeight: 52,
                      fontSize: 18,
                      fontWeight: 600,
                      borderRadius: "6px",
                      border: "2px solid",
                      borderColor: "#35665e",
                      color: "#35665e",
                      bgcolor: "transparent",
                      transition: "border-color 75ms ease-out",
                      "&:hover": {
                        border: "2px solid #234b44",
                        bgcolor: "transparent",
                      },
                      "&.Mui-disabled": {
                        borderColor: "action.disabledBackground",
                        color: "action.disabled",
                      },
                    }}
                  >
                    Find matches
                  </Button>
                )}
                {!photo && !preparing && (
                  <Typography component="p" color="text.secondary" sx={{ fontSize: 13, mt: 2 }}>
                    or try an{" "}
                    <Button
                      id="example-button"
                      onClick={chooseExample}
                      sx={{
                        textDecoration: "underline",
                        textUnderlineOffset: "3px",
                        minWidth: 0,
                        p: "6px 2px",
                        fontSize: "inherit",
                      }}
                    >
                      example
                    </Button>
                  </Typography>
                )}
              </Box>
              {photo && preview && (
                <Typography sx={{ fontSize: 12, mt: 1, lineHeight: 1.7 }} color="text.secondary">
                  This design preview makes no provider calls. A small reference thumbnail stays in
                  this tab with historical example results.
                </Typography>
              )}
              {error && (
                <Typography
                  id="upload-error"
                  role="alert"
                  color="error"
                  sx={{ mt: 2, fontSize: 13 }}
                >
                  {error}
                </Typography>
              )}
            </Box>
          )}
          {failure && (
            <Accordion
              disableGutters
              elevation={0}
              sx={{
                mt: 2,
                width: "min(100%, 520px)",
                minWidth: 0,
                maxWidth: "100%",
                textAlign: "left",
                bgcolor: "transparent",
                "&::before": { display: "none" },
              }}
            >
              <AccordionSummary
                expandIcon={
                  <Box component="span" aria-hidden="true">
                    ⌄
                  </Box>
                }
                aria-controls="failure-explanation"
              >
                <Typography sx={{ fontSize: 14, fontWeight: 700 }}>
                  How this search worked
                </Typography>
              </AccordionSummary>
              <AccordionDetails id="failure-explanation" sx={{ px: 0, minWidth: 0 }}>
                <SearchWalkthrough result={failure} />
              </AccordionDetails>
            </Accordion>
          )}
        </Box>
      )}
    </Box>
  );
}

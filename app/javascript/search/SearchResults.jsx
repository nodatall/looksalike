import { useState } from "react";
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Box,
  Button,
  Card,
  CardContent,
  IconButton,
  Typography,
} from "@mui/material";
import SearchWalkthrough from "./SearchWalkthrough";
import { listingPage } from "./listingPages";

function ListingImage({ listing }) {
  const [broken, setBroken] = useState(false);
  return (
    <Box
      sx={{
        height: { xs: 160, sm: 215 },
        flexShrink: 0,
        minHeight: 0,
        minWidth: 0,
        overflow: "hidden",
        bgcolor: "#ebece5",
        display: "grid",
        placeItems: "center",
      }}
    >
      {broken ? (
        <Typography sx={{ fontSize: 13, p: 2 }} color="text.secondary">
          Listing photo unavailable
        </Typography>
      ) : (
        <Box
          component="img"
          src={listing.thumbnail}
          alt={listing.title}
          loading="lazy"
          referrerPolicy="no-referrer"
          onError={() => setBroken(true)}
          sx={{
            display: "block",
            width: "100%",
            height: "100%",
            minHeight: 0,
            minWidth: 0,
            maxHeight: "100%",
            objectFit: "contain",
          }}
        />
      )}
    </Box>
  );
}
export function listingPrice(price) {
  if (!price) return null;
  if (price.from && price.to)
    return price.from === price.to ? price.from : `${price.from} – ${price.to}`;
  if (price.from) return `From ${price.from}`;
  if (price.to) return `Up to ${price.to}`;
  return price.raw || null;
}
export function listingShipping(shipping) {
  if (!shipping) return null;
  const quote = shipping
    .trim()
    .replace(/^\+\s*/, "")
    .replace(/\bprior to delivery\b/gi, "before arrival")
    .replace(/\bdelivery\b/gi, "shipping");
  if (!quote) return null;
  return /\b(?:shipping|pickup)\b/i.test(quote) ? quote : `${quote} shipping`;
}
export default function SearchResults({
  result,
  reference,
  restored,
  explanationOpen,
  onExplanationChange,
  onAgain,
  headingRef,
  storageAvailable,
  page = 0,
  onPageChange,
}) {
  const saved = restored || result.source === "cache";
  const listings = result.listings;
  const current = listingPage(listings, page);
  return (
    <Box component="section" sx={{ width: "min(100%, 1030px)", mx: "auto", py: { xs: 4, sm: 7 } }}>
      <Box sx={{ display: "flex", alignItems: "center", gap: { xs: 1, sm: 2 }, mb: 3 }}>
        {reference && (
          <Box
            component="img"
            src={reference}
            alt="Reference furniture"
            sx={{
              width: { xs: 48, sm: 64 },
              height: { xs: 48, sm: 64 },
              objectFit: "contain",
              borderRadius: 1,
            }}
          />
        )}
        <Typography
          ref={headingRef}
          tabIndex={-1}
          component="h1"
          variant="h1"
          sx={{ fontSize: { xs: 26, sm: 36 }, whiteSpace: "nowrap", outline: "none" }}
        >
          Similar Items
        </Typography>
        <Button
          onClick={onAgain}
          sx={{ ml: "auto", flexShrink: 0, fontSize: { xs: 12, sm: 14 }, minWidth: 0, px: 1 }}
        >
          Search again
        </Button>
      </Box>
      {(saved || result.source === "snapshot") && (
        <Typography sx={{ fontSize: 12, mb: 3 }} color="text.secondary">
          {result.source === "snapshot"
            ? "Historical snapshot"
            : restored
              ? "Restored in this tab"
              : "Cached result"}{" "}
          ·{" "}
          {new Date(result.retrieved_at).toLocaleDateString("en-US", {
            month: "long",
            day: "numeric",
            year: "numeric",
            timeZone: "UTC",
          })}
        </Typography>
      )}
      {!storageAvailable && (
        <Typography sx={{ fontSize: 12, mb: 2 }} color="text.secondary">
          This browser could not save the result for reload.
        </Typography>
      )}
      {listings.length === 0 ? (
        <Box sx={{ bgcolor: "background.paper", p: 4, borderRadius: 2, mb: 4 }}>
          <Typography component="h2" sx={{ fontSize: 20, mb: 1 }}>
            No matches found
          </Typography>
          <Typography sx={{ fontSize: 14 }}>
            No listings met this search’s furniture and US-location checks. Search again with
            another photo or try the example.
          </Typography>
        </Box>
      ) : (
        <Box
          sx={{
            "--listing-card-height": { xs: "360px", sm: "415px" },
            display: "grid",
            gridTemplateColumns: {
              xs: "repeat(2, minmax(0, 1fr))",
              md: "repeat(3, minmax(0, 1fr))",
            },
            gridAutoRows: "var(--listing-card-height)",
            gridTemplateRows:
              current.pageCount > 1
                ? {
                    xs: "repeat(3, var(--listing-card-height))",
                    md: "repeat(2, var(--listing-card-height))",
                  }
                : undefined,
            gap: { xs: 1.5, sm: 3 },
            mb: current.pageCount > 1 ? 3 : 5,
          }}
        >
          {current.listings.map((listing) => (
            <Card
              key={listing.id}
              variant="outlined"
              sx={{
                borderRadius: 2,
                overflow: "hidden",
                bgcolor: "background.paper",
                height: "100%",
              }}
            >
              <Box
                component="a"
                href={listing.url}
                target="_blank"
                rel="noopener noreferrer"
                sx={{
                  display: "flex",
                  flexDirection: "column",
                  color: "inherit",
                  textDecoration: "none",
                  height: "100%",
                  "&:hover h2": { textDecoration: "underline" },
                  "&:focus-visible": { outline: "3px solid #36563d", outlineOffset: -3 },
                }}
              >
                <ListingImage listing={listing} />
                <CardContent
                  sx={{
                    px: { xs: 1.5, sm: 2 },
                    pt: 2,
                    "&:last-child": { pb: 2 },
                    flexGrow: 1,
                    minHeight: 0,
                    display: "flex",
                    flexDirection: "column",
                  }}
                >
                  <Typography
                    component="h2"
                    sx={{
                      fontSize: { xs: 14, sm: 16 },
                      fontWeight: 550,
                      lineHeight: 1.4,
                      mb: 1,
                      minHeight: "4.2em",
                      overflowWrap: "anywhere",
                      display: "-webkit-box",
                      WebkitLineClamp: 3,
                      WebkitBoxOrient: "vertical",
                      overflow: "hidden",
                    }}
                  >
                    {listing.title}
                  </Typography>
                  {listingPrice(listing.price) && (
                    <Typography
                      sx={{
                        fontWeight: 650,
                        fontSize: 16,
                        lineHeight: 1.4,
                        mb: 0.75,
                        display: "-webkit-box",
                        WebkitLineClamp: 2,
                        WebkitBoxOrient: "vertical",
                        overflow: "hidden",
                      }}
                    >
                      {listingPrice(listing.price)}
                    </Typography>
                  )}
                  {listingShipping(listing.shipping) && (
                    <Typography
                      sx={{
                        fontSize: 12,
                        lineHeight: 1.6,
                        display: "-webkit-box",
                        WebkitLineClamp: 2,
                        WebkitBoxOrient: "vertical",
                        overflow: "hidden",
                      }}
                      color="text.secondary"
                    >
                      {listingShipping(listing.shipping)}
                    </Typography>
                  )}
                </CardContent>
              </Box>
            </Card>
          ))}
        </Box>
      )}
      {current.pageCount > 1 && (
        <Box
          component="nav"
          aria-label="Result pages"
          sx={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 1, mb: 5 }}
        >
          <IconButton
            aria-label="Previous page"
            disableRipple
            disabled={current.page === 0}
            onClick={() => onPageChange(current.page - 1)}
            sx={{
              width: 40,
              height: 40,
              "&:hover": { bgcolor: "transparent", color: "primary.main" },
              "&.Mui-focusVisible": { outline: "2px solid #36563d", outlineOffset: 2 },
            }}
          >
            <Box
              component="svg"
              viewBox="0 0 24 24"
              aria-hidden="true"
              sx={{ width: 24, height: 24 }}
            >
              <path
                d="m14 6-6 6 6 6"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </Box>
          </IconButton>
          <Typography
            aria-live="polite"
            aria-atomic="true"
            sx={{ fontSize: 14, minWidth: 80, textAlign: "center" }}
          >
            {current.page + 1} / {current.pageCount}
          </Typography>
          <IconButton
            aria-label="Next page"
            disableRipple
            disabled={current.page === current.pageCount - 1}
            onClick={() => onPageChange(current.page + 1)}
            sx={{
              width: 40,
              height: 40,
              "&:hover": { bgcolor: "transparent", color: "primary.main" },
              "&.Mui-focusVisible": { outline: "2px solid #36563d", outlineOffset: 2 },
            }}
          >
            <Box
              component="svg"
              viewBox="0 0 24 24"
              aria-hidden="true"
              sx={{ width: 24, height: 24 }}
            >
              <path
                d="m10 6 6 6-6 6"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </Box>
          </IconButton>
        </Box>
      )}
      <Accordion
        disableGutters
        elevation={0}
        expanded={explanationOpen}
        onChange={(_event, open) => onExplanationChange(open)}
        sx={{
          bgcolor: "transparent",
          borderTop: 1,
          borderColor: "divider",
          "&::before": { display: "none" },
        }}
      >
        <AccordionSummary
          expandIcon={
            <Box component="span" aria-hidden="true">
              ⌄
            </Box>
          }
          aria-controls="search-explanation"
          id="search-explanation-heading"
          sx={{ px: 0 }}
        >
          <Typography sx={{ fontSize: 14, fontWeight: 700 }}>How this search worked</Typography>
        </AccordionSummary>
        <AccordionDetails id="search-explanation" sx={{ px: 0, pt: 2 }}>
          <SearchWalkthrough result={result} restored={restored} />
        </AccordionDetails>
      </Accordion>
    </Box>
  );
}

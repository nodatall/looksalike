export const LISTINGS_PER_PAGE = 6;
export const MAX_LISTINGS = 100;

export function listingPage(listings, requestedPage = 0) {
  const pageCount = Math.max(1, Math.ceil(listings.length / LISTINGS_PER_PAGE));
  const page = Math.max(0, Math.min(pageCount - 1, requestedPage));
  return {
    page,
    pageCount,
    listings: listings.slice(page * LISTINGS_PER_PAGE, (page + 1) * LISTINGS_PER_PAGE),
  };
}

import assert from "node:assert/strict";
import test from "node:test";
import { listingPage } from "../../app/javascript/search/listingPages.js";

test("pages retain every accepted listing in order, with six cards and a shorter last page", () => {
  const listings = Array.from({ length: 52 }, (_, id) => ({ id }));
  const pages = Array.from({ length: 9 }, (_, page) => listingPage(listings, page));
  assert.deepEqual(
    pages.map((page) => page.listings.length),
    [6, 6, 6, 6, 6, 6, 6, 6, 4],
  );
  assert.deepEqual(
    pages.flatMap((page) => page.listings),
    listings,
  );
  assert.equal(listingPage(listings, -1).page, 0);
  assert.equal(listingPage(listings, 9).page, 8);
});

test("empty and single-page results stay on the first page", () => {
  for (const length of [0, 1, 6]) {
    const listings = Array.from({ length }, (_, id) => ({ id }));
    assert.deepEqual(listingPage(listings, 3), { page: 0, pageCount: 1, listings });
  }
});

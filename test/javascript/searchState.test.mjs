import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  clearSavedView,
  readSavedView,
  safeItemUrl,
  safeReference,
  safeThumbnailUrl,
  saveView,
  STORAGE_KEY,
  validateCompletedResult,
} from "../../app/javascript/search/searchState.js";

// Permanent table coverage protects the supported saved-view URL/privacy boundary.
const snapshot = JSON.parse(
  await readFile(new URL("../../app/javascript/search/modernSofa.json", import.meta.url)),
);
const copy = () => structuredClone(snapshot);
function storage() {
  const entries = new Map();
  return {
    getItem: (key) => entries.get(key) ?? null,
    setItem: (key, value) => entries.set(key, value),
    removeItem: (key) => entries.delete(key),
  };
}

for (const [kind, validator, accepted, rejected] of [
  [
    "item",
    safeItemUrl,
    ["https://www.ebay.com/itm/336737755519"],
    [
      "http://www.ebay.com/itm/123",
      "https://ebay.com/itm/123",
      "https://www.ebay.com.evil.test/itm/123",
      "https://user:password@www.ebay.com/itm/123",
      "https://www.ebay.com:443/itm/123",
      "https://www.ebay.com/itm/123?token=secret",
      "https://www.ebay.com/itm/123#payload",
      "https://www.ebay.com/itm/0",
      "javascript:alert(1)",
      "//www.ebay.com/itm/123",
    ],
  ],
  [
    "thumbnail",
    safeThumbnailUrl,
    [snapshot.listings[0].thumbnail, "https://i.ebayimg.com/images/g/example/s-l500.jpg"],
    [
      "https://i.ebayimg.com.evil.test/image.jpg",
      "https://user@i.ebayimg.com/image.jpg",
      "http://i.ebayimg.com/image.jpg",
      "https://i.ebayimg.com:444/image.jpg",
      "https://i.ebayimg.com/a.svg",
      "https://i.ebayimg.com/a.jpg?api_key=secret",
      "https://i.ebayimg.com/a.jpg#secret",
      "https://i.ebayimg.com/%2e%2e/a.jpg",
      "https://i.ebayimg.com/a/../b.jpg",
      "https://i.ebayimg.com/a\\b.jpg",
      "data:image/jpeg;base64,aA==",
    ],
  ],
]) {
  test(`${kind} URL allowlist accepts exact supported URLs and rejects unsafe variations`, () => {
    for (const value of accepted) assert.equal(validator(value), true, value);
    for (const value of rejected) assert.equal(validator(value), false, value);
  });
}

test("saved success and empty views replay without requests and preserve the original record", () => {
  const previous = globalThis.fetch;
  globalThis.fetch = () => assert.fail("restoration must never make a request");
  try {
    for (const status of ["success", "empty"]) {
      const result = copy();
      if (status === "empty") {
        result.status = status;
        result.listings = [];
      }
      const store = storage();
      const view = { result, reference: null, explanationOpen: true };
      assert.equal(saveView(store, view), true);
      assert.deepEqual(readSavedView(store), view);
      assert.deepEqual(readSavedView(store).result.attempts, { uploads: 0, serpapi: 0, vision: 0 });
      clearSavedView(store);
      assert.equal(readSavedView(store), null);
    }
  } finally {
    globalThis.fetch = previous;
  }
});

test("corrupt, legacy and unsafe completed records cannot be restored", () => {
  const changes = [
    (result) => {
      result.version = "craigslist-v1";
    },
    (result) => {
      result.marketplace = "craigslist.org";
    },
    (result) => {
      result.scope = "94103";
    },
    (result) => {
      result.retrieved_at = "2026-02-30T10:00:00Z";
    },
    (result) => {
      result.source = "other";
    },
    (result) => {
      result.listings[0].url += "?credential=secret";
    },
    (result) => {
      result.listings[0].id = "123";
    },
    (result) => {
      result.listings[0].thumbnail = "https://other.test/photo.jpg";
    },
    (result) => {
      result.listings.push(result.listings[0]);
    },
    (result) => {
      result.listings[0].location = "San Francisco";
    },
    (result) => {
      result.stages[0].request.parameters.image_id = "private-reference";
    },
    (result) => {
      result.raw_response = { payload: "private" };
    },
    (result) => {
      result.query_preparation.api_key = "secret";
    },
    (result) => {
      result.original_attempts.serpapi = -1;
    },
    (result) => {
      result.attempts.vision = 1;
    },
    (result) => {
      result.status = "started";
    },
    (result) => {
      result.stages[0].status = "started";
    },
    (result) => {
      result.stages[0].status = "failed";
    },
    (result) => {
      result.status = "empty";
    },
  ];
  for (const mutate of changes) {
    const result = copy();
    mutate(result);
    assert.equal(validateCompletedResult(result), null);
    const store = storage();
    store.setItem(
      STORAGE_KEY,
      JSON.stringify({ version: "ebay-us-v1", result, reference: null, explanationOpen: false }),
    );
    assert.equal(readSavedView(store), null);
  }
  const store = storage();
  for (const raw of [
    "{",
    "null",
    JSON.stringify({ zip: "94103", cards: [] }),
    JSON.stringify({
      version: "ebay-us-v1",
      result: snapshot,
      reference: null,
      explanationOpen: false,
      original_photo: "private",
    }),
  ]) {
    store.setItem(STORAGE_KEY, raw);
    assert.equal(readSavedView(store), null);
  }
  assert.equal(
    readSavedView({
      getItem() {
        throw new Error("disabled");
      },
    }),
    null,
  );
  assert.equal(
    saveView(
      {
        setItem() {
          throw new Error("quota");
        },
      },
      { result: snapshot, reference: null, explanationOpen: false },
    ),
    false,
  );
  assert.equal(
    saveView(storage(), {
      result: snapshot,
      reference: null,
      explanationOpen: false,
      raw: "private",
    }),
    false,
  );
});

test("only bounded JPEG reference thumbnails may be restored", async () => {
  const small = await readFile(new URL("../fixtures/files/photo.jpg", import.meta.url));
  const large = await readFile(
    new URL("../../app/javascript/search/assets/modern-sofa.jpg", import.meta.url),
  );
  const thumbnail = `data:image/jpeg;base64,${small.toString("base64")}`;
  assert.equal(safeReference(thumbnail), true);
  for (const bad of [
    `data:image/jpeg;base64,${large.toString("base64")}`,
    "data:image/svg+xml;base64,aA==",
    "https://example.test/photo.jpg",
    "data:image/jpeg;base64,aA==",
  ])
    assert.equal(safeReference(bad), false);
  const store = storage();
  assert.equal(
    saveView(store, { result: snapshot, reference: thumbnail, explanationOpen: false }),
    true,
  );
  assert.equal(readSavedView(store).reference, thumbnail);
});

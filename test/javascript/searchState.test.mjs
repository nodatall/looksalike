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
const copy = () => ({ ...structuredClone(snapshot), source: "cache" });
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
    for (const [source, status] of [
      ["live", "success"],
      ["live", "empty"],
      ["cache", "success"],
      ["cache", "empty"],
    ]) {
      const result = copy();
      result.source = source;
      if (source === "live") result.attempts = structuredClone(result.original_attempts);
      if (status === "empty") {
        result.status = status;
        result.listings = [];
      }
      const store = storage();
      const view = { result, reference: null, explanationOpen: true };
      assert.equal(saveView(store, view), true);
      assert.deepEqual(readSavedView(store), view);
      assert.deepEqual(readSavedView(store).result.attempts, result.attempts);
      clearSavedView(store);
      assert.equal(readSavedView(store), null);
    }
  } finally {
    globalThis.fetch = previous;
  }
});

test("historical sponsored rejection counts remain readable in saved results", () => {
  const result = copy();
  const summary = result.stages.find((stage) => stage.stage === "filter").summary;
  summary.sponsored = 3;
  assert.deepEqual(validateCompletedResult(result), result);
  const store = storage();
  assert.equal(saveView(store, { result, reference: null, explanationOpen: false }), true);
  assert.equal(
    readSavedView(store).result.stages.find((stage) => stage.stage === "filter").summary.sponsored,
    3,
  );
  for (const invalid of [-1, 101, "3"]) {
    summary.sponsored = invalid;
    assert.equal(validateCompletedResult(result), null);
  }
});

test("all accepted listings and the current page survive reload without another search", () => {
  const result = copy();
  result.listings = Array.from({ length: 100 }, (_, index) => ({
    ...result.listings[0],
    id: String(index + 1),
    url: `https://www.ebay.com/itm/${index + 1}`,
    thumbnail: `https://i.ebayimg.com/images/${"x".repeat(1200)}${index}.jpg`,
  }));
  const view = { result, reference: null, explanationOpen: false, page: 16 };
  assert.ok(JSON.stringify(view).length > 100_000);
  const store = storage();
  const previous = globalThis.fetch;
  globalThis.fetch = () => assert.fail("pagination and reload must never search again");
  try {
    assert.equal(saveView(store, view), true);
    assert.deepEqual(readSavedView(store), view);
    for (const page of [-1, 17, 0.5, null, "1"]) {
      const invalid = { ...view, page };
      assert.equal(saveView(store, invalid), false);
      store.setItem(STORAGE_KEY, JSON.stringify({ version: "ebay-us-v1", ...invalid }));
      assert.equal(readSavedView(store), null);
    }
  } finally {
    globalThis.fetch = previous;
  }
  result.listings.push({ ...result.listings[0], id: "101", url: "https://www.ebay.com/itm/101" });
  assert.equal(validateCompletedResult(result), null);
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
      result.source = "snapshot";
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
    assert.equal(saveView(store, { result, reference: null, explanationOpen: false }), false);
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
      result: copy(),
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
      { result: copy(), reference: null, explanationOpen: false },
    ),
    false,
  );
  assert.equal(
    saveView(storage(), {
      result: copy(),
      reference: null,
      explanationOpen: false,
      raw: "private",
    }),
    false,
  );
});

test("old runtime keys and preview snapshots cannot restore as current runtime results", () => {
  for (const result of [copy(), snapshot]) {
    const store = storage();
    const view = { result, reference: null, explanationOpen: false };
    store.setItem("looksalike:ebay-us-v1", JSON.stringify({ version: "ebay-us-v1", ...view }));
    assert.equal(readSavedView(store), null);
  }
  const store = storage();
  const view = { result: snapshot, reference: null, explanationOpen: true };
  assert.equal(validateCompletedResult(snapshot), null);
  assert.equal(saveView(store, view), false);
  assert.equal(saveView(store, view, { preview: true }), true);
  assert.deepEqual(readSavedView(store, { preview: true }), view);
  assert.equal(readSavedView(store), null);
  clearSavedView(store);
  assert.deepEqual(readSavedView(store, { preview: true }), view);
  clearSavedView(store, { preview: true });
  assert.equal(readSavedView(store, { preview: true }), null);
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
    saveView(store, { result: copy(), reference: thumbnail, explanationOpen: false }),
    true,
  );
  assert.equal(readSavedView(store).reference, thumbnail);
});

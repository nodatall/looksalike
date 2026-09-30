import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  readSearchResponse,
  SearchResponseError,
  submitPhoto,
} from "../../app/javascript/search/searchProtocol.js";

// Permanent protocol coverage protects incremental progress, cancellation and no-retry spending.
const snapshot = JSON.parse(
  await readFile(new URL("../../app/javascript/search/modernSofa.json", import.meta.url)),
);
const stage = (status, extra = {}) => ({ type: "stage", stage: "upload", status, ...extra });
const line = (event) => `${JSON.stringify(event)}\n`;
const resultLine = line({ type: "result", result: snapshot });
function response(text, split = 7) {
  const bytes = new TextEncoder().encode(text);
  return new Response(
    new ReadableStream({
      start(controller) {
        for (let offset = 0; offset < bytes.length; offset += split)
          controller.enqueue(bytes.slice(offset, offset + split));
        controller.close();
      },
    }),
    { headers: { "content-type": "application/x-ndjson" } },
  );
}

test("split NDJSON chunks deliver actual events before the final result", async () => {
  const events = [];
  const result = structuredClone(snapshot);
  result.listings[0].title = "Café sofa";
  const completed = await readSearchResponse(
    response(
      line(stage("started")) +
        line(stage("complete", { duration_ms: 501 })) +
        line({ type: "result", result }),
      1,
    ),
    { onStage: (event) => events.push(event) },
  );
  assert.deepEqual(events, [stage("started"), stage("complete", { duration_ms: 501 })]);
  assert.deepEqual(completed, result);
});

test("malformed, truncated and invalid stage/result boundaries reject the response", async () => {
  for (const text of [
    "{\n",
    resultLine.trimEnd(),
    line(stage("started")),
    line(stage("complete")) + resultLine,
    line(stage("started")) + line(stage("started")) + resultLine,
    line(stage("started", { duration_ms: -1 })) + resultLine,
    line(stage("started", { image_id: "private" })) + resultLine,
    resultLine + resultLine,
    resultLine + line(stage("started")),
    line({ type: "result", result: { ...snapshot, raw_provider: "private" } }),
  ]) {
    await assert.rejects(readSearchResponse(response(text)), SearchResponseError);
  }
  await assert.rejects(
    readSearchResponse(new Response("error", { status: 503 })),
    SearchResponseError,
  );
});

test("small server errors are actionable without requiring a completed-result schema", async () => {
  assert.deepEqual(
    await readSearchResponse(
      response(
        line({
          type: "result",
          result: { status: "invalid_photo", message: "Choose a furniture photo." },
        }),
      ),
    ),
    { status: "invalid_photo", message: "Choose a furniture photo." },
  );
});

test("sanitized failed call details survive streaming but cannot become a saved completed view", async () => {
  const failure = structuredClone(snapshot);
  Object.assign(failure, {
    status: "provider_unavailable",
    source: "live",
    retrieved_at: null,
    message: "The search service is unavailable. Try the example.",
    listings: [],
    stages: [
      {
        stage: "upload",
        status: "failed",
        duration_ms: 501,
        request: structuredClone(snapshot.stages[0].request),
      },
    ],
    attempts: { uploads: 1, serpapi: 0, vision: 0 },
  });
  const restored = await readSearchResponse(
    response(
      line(stage("started")) +
        line(stage("failed", { duration_ms: 501 })) +
        line({ type: "result", result: failure }),
    ),
  );
  assert.deepEqual(restored, failure);
  const { saveView } = await import("../../app/javascript/search/searchState.js");
  assert.equal(
    saveView(
      {
        setItem() {
          assert.fail("failure must never be persisted");
        },
      },
      { result: restored, reference: null, explanationOpen: false },
    ),
    false,
  );
  failure.stages[0].request.parameters.image_id = "private";
  await assert.rejects(
    readSearchResponse(response(line({ type: "result", result: failure }))),
    SearchResponseError,
  );
});

test("abort cancels an incomplete stream and never accepts a late result", async () => {
  let cancelled = false;
  const controller = new AbortController();
  const streamed = new Response(
    new ReadableStream({
      start(stream) {
        stream.enqueue(new TextEncoder().encode(line(stage("started"))));
      },
      cancel() {
        cancelled = true;
      },
    }),
    { headers: { "content-type": "application/x-ndjson" } },
  );
  const reading = readSearchResponse(streamed, {
    signal: controller.signal,
    onStage() {
      controller.abort(new Error("Back"));
    },
  });
  await assert.rejects(reading, { message: "Back" });
  assert.equal(cancelled, true);
});

test("multipart submission uses same-origin CSRF and never retries a failed request", async () => {
  let calls = 0;
  const blob = new Blob(["prepared"], { type: "image/jpeg" });
  const result = await submitPhoto(blob, {
    csrfToken: "test-token",
    fetcher: async (url, options) => {
      calls++;
      assert.equal(url, "/searches");
      assert.equal(options.method, "POST");
      assert.equal(options.credentials, "same-origin");
      assert.equal(options.headers["X-CSRF-Token"], "test-token");
      assert.equal(options.body.get("photo").name, "furniture.jpg");
      return response(resultLine);
    },
  });
  assert.equal(calls, 1);
  assert.deepEqual(result, snapshot);
  calls = 0;
  await assert.rejects(
    submitPhoto(blob, {
      fetcher: async () => {
        calls++;
        throw new Error("offline");
      },
    }),
    { message: "offline" },
  );
  assert.equal(calls, 1);
});

import { STAGES, validateCompletedResult, validateFailureResult } from "./searchState.js";

export class SearchResponseError extends Error {
  constructor() {
    super("The search response was interrupted or unreadable. Please try again.");
  }
}

// Never retry: one browser submission corresponds to one bounded server request.
export async function readSearchResponse(response, { signal, onStage = () => {} } = {}) {
  if (
    !response.ok ||
    !response.headers.get("content-type")?.includes("application/x-ndjson") ||
    !response.body
  )
    throw new SearchResponseError();
  const reader = response.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let pending = "";
  let bytes = 0;
  let final;
  const statuses = new Map();
  const abort = () => {
    void reader.cancel().catch(() => {});
  };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    while (true) {
      signal?.throwIfAborted();
      const { value, done } = await reader.read();
      signal?.throwIfAborted();
      if (done) break;
      bytes += value.length;
      if (bytes > 1_000_000) throw new SearchResponseError();
      pending += decoder.decode(value, { stream: true });
      while (pending.includes("\n")) {
        const end = pending.indexOf("\n");
        const line = pending.slice(0, end);
        pending = pending.slice(end + 1);
        let event;
        try {
          event = JSON.parse(line);
        } catch {
          throw new SearchResponseError();
        }
        if (!event || final) throw new SearchResponseError();
        if (event.type === "stage") {
          if (
            Object.keys(event).some(
              (key) => !["type", "stage", "status", "duration_ms"].includes(key),
            ) ||
            !STAGES.includes(event.stage) ||
            !["started", "complete", "failed"].includes(event.status) ||
            (event.duration_ms !== undefined &&
              (!Number.isFinite(event.duration_ms) ||
                event.duration_ms < 0 ||
                event.duration_ms > 65_000)) ||
            (event.status === "started"
              ? statuses.has(event.stage)
              : statuses.get(event.stage) !== "started")
          )
            throw new SearchResponseError();
          statuses.set(event.stage, event.status);
          onStage(event);
        } else if (
          event.type === "result" &&
          Object.keys(event).length === 2 &&
          event.result &&
          typeof event.result.status === "string"
        ) {
          final = ["success", "empty"].includes(event.result.status)
            ? validateCompletedResult(event.result)
            : validateFailureResult(event.result);
          if (!final) throw new SearchResponseError();
        } else throw new SearchResponseError();
      }
    }
    pending += decoder.decode();
    if (pending || !final) throw new SearchResponseError();
    return final;
  } catch (error) {
    if (signal?.aborted) throw signal.reason;
    if (error instanceof SearchResponseError) throw error;
    throw new SearchResponseError();
  } finally {
    signal?.removeEventListener("abort", abort);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export async function submitPhoto(blob, { signal, onStage, fetcher = fetch, csrfToken } = {}) {
  const body = new FormData();
  body.append("photo", blob, "furniture.jpg");
  const response = await fetcher("/searches", {
    method: "POST",
    body,
    signal,
    credentials: "same-origin",
    headers: { Accept: "application/x-ndjson", "X-CSRF-Token": csrfToken || "" },
  });
  return readSearchResponse(response, { signal, onStage });
}

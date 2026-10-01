import { inspectPhoto } from "./preparePhoto.js";

export const STORAGE_KEY = "looksalike:ebay-us-v2";
const PREVIEW_STORAGE_KEY = "looksalike:mockup:ebay-us-v1";
export const STAGES = ["upload", "lens", "vision", "ebay", "filter"];
const record = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
export const safeText = (max) => (value) =>
  typeof value === "string" &&
  value.length <= max &&
  !/https?:|data:/i.test(value) &&
  Array.from(value).every((char) => char.charCodeAt(0) >= 32 && char.charCodeAt(0) !== 127);
const text = safeText;
const number =
  (max = 1_000_000) =>
  (value) =>
    typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= max;
const oneOf =
  (...values) =>
  (value) =>
    values.includes(value);
const list = (rule, max) => (value) =>
  Array.isArray(value) && value.length <= max && value.every(rule);
const bool = (value) => typeof value === "boolean";
function shape(schema) {
  return (value) =>
    record(value) &&
    Object.keys(value).every((key) => Object.hasOwn(schema, key)) &&
    Object.entries(value).every(([key, supplied]) => supplied === null || schema[key](supplied));
}
const counters = shape({ uploads: number(1), serpapi: number(2), vision: number(1) });
const validCounters = (value) =>
  counters(value) && ["uploads", "serpapi", "vision"].every((key) => Number.isInteger(value[key]));
const usage = shape({ input_tokens: number(), output_tokens: number(), total_tokens: number() });
const preparationFields = {
  status: text(40),
  source: oneOf("lens", "vision"),
  query: text(90),
  category: text(40),
  lens_query: text(90),
  lens_category: text(40),
  lens_version: text(60),
  trigger_version: text(60),
  phrase_version: text(60),
  fallback_reason: text(100),
  provider: oneOf("venice"),
  model: text(100),
  prompt_version: text(60),
  schema_version: text(60),
  duration_ms: number(65_000),
  usage,
  traits: list(text(30), 2),
};
const reasons = shape(
  Object.fromEntries(
    [
      "missing_title",
      "miniature",
      "accessory_or_part",
      "different_item",
      "missing_furniture_type",
      "wrong_category",
      "mixed_categories",
    ].map((key) => [key, number(100)]),
  ),
);
const summary = shape({
  ...preparationFields,
  photo_reference_received: bool,
  visual_matches: number(1000),
  titles: list(text(300), 8),
  returned: number(100),
  invalid_url: number(100),
  missing_metadata: number(100),
  not_explicit_us: number(100),
  duplicate: number(100),
  eligible: number(100),
  title_rejected: number(100),
  title_rejection_reasons: reasons,
  accepted: number(100),
  displayed: number(6),
  reason: text(100),
  note: text(300),
});
const parameterFields = {
  format: oneOf("image/jpeg"),
  bytes: number(450_000),
  engine: oneOf("google_lens", "ebay"),
  type: oneOf("all"),
  country: oneOf("us"),
  hl: oneOf("en"),
  _nkw: text(90),
  ebay_domain: oneOf("ebay.com"),
  _ipg: oneOf("25"),
  provider: oneOf("venice"),
  model: text(100),
  transport_version: text(60),
  prompt_version: text(60),
  schema_version: text(60),
  location_rule: text(60),
  normalizer_version: text(60),
  title_filter_version: text(60),
};
const request = shape({
  provider: oneOf("serpapi", "venice", "local"),
  endpoint: oneOf("/image", "/search.json", "/api/v1/chat/completions"),
  parameters: shape(parameterFields),
});
const stageRule = shape({
  stage: oneOf(...STAGES),
  status: oneOf("started", "complete", "failed", "skipped"),
  duration_ms: number(65_000),
  request,
  summary,
});
const validStage = (value) =>
  stageRule(value) && STAGES.includes(value.stage) && typeof value.status === "string";

export function safeItemUrl(value) {
  return (
    typeof value === "string" && /^https:\/\/www\.ebay\.com\/itm\/[1-9][0-9]{0,19}$/.test(value)
  );
}
export function safeThumbnailUrl(value) {
  // Exact host and ordinary image paths; no credentials, ports, query strings or fragments.
  return (
    typeof value === "string" &&
    value.length <= 2048 &&
    /^https:\/\/i\.ebayimg\.com\/[a-zA-Z0-9_~./%-]+\.(?:jpg|jpeg|png|webp)$/i.test(value) &&
    !/%(?:2f|5c|2e|00)/i.test(value) &&
    !value.includes("/../") &&
    !value.includes("/./")
  );
}
const cardRule = shape({
  id: (value) => /^[1-9][0-9]{0,19}$/.test(value),
  title: text(300),
  url: safeItemUrl,
  thumbnail: safeThumbnailUrl,
  sponsored: bool,
  price: shape({ raw: text(80), from: text(80), to: text(80) }),
  condition: text(100),
  shipping: text(200),
  location: oneOf("Located in United States"),
});
const validCard = (value) =>
  cardRule(value) &&
  typeof value.id === "string" &&
  typeof value.title === "string" &&
  value.title.trim().length > 0 &&
  safeItemUrl(value.url) &&
  value.url.endsWith(`/${value.id}`) &&
  safeThumbnailUrl(value.thumbnail) &&
  typeof value.sponsored === "boolean" &&
  value.location === "Located in United States";
const isoDate = (value) =>
  typeof value === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value) &&
  Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString().slice(0, 19) === value.slice(0, 19);
const resultFields = {
  version: oneOf("ebay-us-v1"),
  status: oneOf("success", "empty"),
  source: oneOf("live", "cache"),
  marketplace: oneOf("ebay.com"),
  scope: oneOf("us"),
  message: text(300),
  retrieved_at: isoDate,
  query: text(90),
  category: text(40),
  query_preparation: shape(preparationFields),
  listings: list(validCard, 6),
  stages: list(validStage, 5),
  attempts: validCounters,
  original_attempts: validCounters,
};
// Historical results are accepted only by the standalone preview's explicit option.
const completedRule = (preview) =>
  shape({
    ...resultFields,
    source: preview ? oneOf("live", "cache", "snapshot") : resultFields.source,
  });

export function validateFailureResult(value) {
  if (
    !shape({ ...resultFields, status: text(40) })(value) ||
    !text(40)(value.status) ||
    ["success", "empty"].includes(value.status) ||
    (value.listings !== undefined &&
      (!Array.isArray(value.listings) || value.listings.length !== 0))
  )
    return null;
  return JSON.parse(JSON.stringify(value));
}

export function validateCompletedResult(value, { preview = false } = {}) {
  if (
    !completedRule(preview)(value) ||
    value.version !== "ebay-us-v1" ||
    value.marketplace !== "ebay.com" ||
    value.scope !== "us" ||
    !isoDate(value.retrieved_at) ||
    !(preview ? ["live", "cache", "snapshot"] : ["live", "cache"]).includes(value.source) ||
    !Array.isArray(value.listings) ||
    !Array.isArray(value.stages) ||
    value.stages.some(
      (entry) =>
        entry.status !== "complete" && !(entry.stage === "vision" && entry.status === "skipped"),
    ) ||
    !validCounters(value.attempts) ||
    !validCounters(value.original_attempts) ||
    (value.status === "success"
      ? value.listings.length === 0
      : value.status !== "empty" || value.listings.length !== 0) ||
    new Set(value.listings.map((card) => card.id)).size !== value.listings.length ||
    new Set(value.stages.map((entry) => entry.stage)).size !== value.stages.length ||
    (["cache", "snapshot"].includes(value.source) &&
      Object.values(value.attempts).some((count) => count !== 0))
  )
    return null;
  return JSON.parse(JSON.stringify(value));
}

export function safeReference(value) {
  if (value === null) return true;
  if (
    typeof value !== "string" ||
    value.length > 40_000 ||
    !/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(value)
  )
    return false;
  try {
    const bytes = Uint8Array.from(atob(value.split(",")[1]), (char) => char.charCodeAt(0));
    const photo = inspectPhoto(bytes, "image/jpeg");
    return Math.max(photo.width, photo.height) <= 160;
  } catch {
    return false;
  }
}
export function readSavedView(storage, { preview = false } = {}) {
  try {
    const raw = storage.getItem(preview ? PREVIEW_STORAGE_KEY : STORAGE_KEY);
    if (!raw || raw.length > 100_000) return null;
    const value = JSON.parse(raw);
    if (
      !shape({
        version: oneOf("ebay-us-v1"),
        result: completedRule(preview),
        reference: safeReference,
        explanationOpen: bool,
      })(value) ||
      value.version !== "ebay-us-v1" ||
      !safeReference(value.reference) ||
      typeof value.explanationOpen !== "boolean"
    )
      return null;
    const result = validateCompletedResult(value.result, { preview });
    return result
      ? { result, reference: value.reference, explanationOpen: value.explanationOpen }
      : null;
  } catch {
    return null;
  }
}
export function clearSavedView(storage, { preview = false } = {}) {
  try {
    storage.removeItem(preview ? PREVIEW_STORAGE_KEY : STORAGE_KEY);
  } catch {
    /* Private mode may disable storage. */
  }
}
export function saveView(storage, view, { preview = false } = {}) {
  try {
    if (
      !shape({ result: completedRule(preview), reference: safeReference, explanationOpen: bool })(
        view,
      ) ||
      !validateCompletedResult(view.result, { preview }) ||
      !safeReference(view.reference) ||
      typeof view.explanationOpen !== "boolean"
    )
      return false;
    storage.setItem(
      preview ? PREVIEW_STORAGE_KEY : STORAGE_KEY,
      JSON.stringify({ version: "ebay-us-v1", ...view }),
    );
    return true;
  } catch {
    return false;
  }
}

export async function referenceThumbnail(blob, signal) {
  let bitmap;
  try {
    bitmap = await createImageBitmap(blob);
    signal?.throwIfAborted();
    const scale = Math.min(1, 160 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const context = canvas.getContext("2d", { alpha: false });
    if (!context) return null;
    context.fillStyle = "#fff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/jpeg", 0.7);
  } finally {
    bitmap?.close();
  }
}

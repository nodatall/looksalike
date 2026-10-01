# Architecture

## Purpose

LooksAlike turns one furniture photo into up to six US-located eBay listings. This document records the implemented server, browser and container boundaries; [hosted deployment evidence](deployment.md) records the Railway checks and real public-photo search.

## Current system shape

Rails 8.1 on Ruby 3.4 serves an ERB shell and one bundled React/Material UI root. `POST /searches` runs the eBay flow and streams real progress. `SearchApp` reduces uploads, consumes that NDJSON contract, shows loading stages/eBay cards and restores valid current-tab results. `/up` remains a cheap health check. The standalone mockup imports shared app components; the app never imports `tasks/`.

The server validates the reduced JPEG, checks the cache, reserves allowance and the single live-search lease, uploads to SerpApi, searches Google Lens, asks Venice only when Lens lacks concrete details, searches eBay and filters listings. This flow has no ZIP, description field, arbitrary URL fetch, job queue or object storage. Live calls default to disabled; both provider keys and valid limits are required.

## Module map

| Module | Owns | Does not own |
| --- | --- | --- |
| `SearchesController` | CSRF, request-thread visitor identity, multipart input, NDJSON stream, disconnect cleanup | Query or quota policy |
| `EbaySearch` | Sequential flow, shared deadline, real stages, sanitized response | HTTP implementation, database policy or browser state |
| `PhotoValidator`, `SearchDeadline` | Bounded image decoding, upload cleanup, monotonic time budget | Search policy or credentials |
| `SerpApi::Client`, `Vision::Client` and transports | Fixed endpoints, credentials, response bounds, no retries, safe errors | Persistence or presentation |
| `SearchQuery`, `PhotoQuery`, `EbayQueryPreparation` | Lens phrase, fallback trigger and strict photo-description validation | Upload/eBay traffic or quotas |
| `EbayListingNormalizer`, `EbayListingFilter` | URL/US eligibility, duplicates, complete-item checks, first-six provider order | Network access or visual ranking |
| `SearchSettings`, `SearchStore` | Validated ceilings, versioned cache, allowance reservations and lease ownership | HTTP or stored photos |
| `ProductionStorage`, production startup | Actual mount, resolved SQLite path, write access, ownership and preparation before serving | Provider calls or web-process health |
| `SearchCacheEntry`, `SearchUsageReservation`, `SearchLease` | Concrete SQLite records | Provider calls |
| `app/javascript/search/` | Photo reduction, NDJSON parsing, loading/results/explanation, versioned session restoration and licensed example-photo selection | Credentials or authority over limits |
| `FurnitureSearch`, location/Craigslist policies, `Experiment*` | Existing historical workflows and their original interface | The public eBay route |

## Dependency rules

The controller composes the flow with real clients and the concrete store. The flow depends on pure policies and two edges: HTTP and persistence. Policies never connect to the network or start a database transaction. Every store transaction ends before provider traffic.

A public upload must be a still JPEG of at most 450 KB with neither edge above 1600 pixels. The server checks this before reserving allowance. Browser preprocessing continues to accept original JPEG, PNG and WebP photos and reduce them to JPEG. Uploaded files are transient request data and close on every exit. Photo bytes, raw responses, credentials and upload references never enter the public explanation or result database. Provider text is bounded and redacted; the browser must render it as text.

The eBay request fixes `engine=ebay`, `ebay_domain=ebay.com` and `_ipg=25`. It omits postal, pickup and country filters. Cards need an individual-item HTTPS URL on `ebay.com` or `www.ebay.com`, a credential-free HTTPS thumbnail on `i.ebayimg.com`, a title and the exact returned location `Located in United States`. Canonical item IDs identify duplicates. Promoted rows follow identical rules. Only supplied price/range, condition and shipping text survives; missing values stay missing. There is no invented city, delivery coverage or similarity score.

Venice uses the fixed `qwen3-vl-235b-a22b` model and versioned strict prompt/schema. It gets at most 15 seconds within the shared deadline, preserving 10 seconds for eBay, and runs at most once. Failed/unclear recognition skips eBay. The title filter checks complete furniture identity; it does not rank visual similarity. The historical Craigslist normalizer's fixed credential-parameter vocabulary is shared by the URL checks without changing historical behavior.

## Persistence and concurrency

Three operational tables use the application's SQLite database. `search_cache_entries` stores sanitized success/empty responses with a unique `fingerprint` and expiry. Identity includes reduced-photo SHA-256, eBay/US rule, normalizer, title filter, Lens query, fallback/phrase policy and Venice model/prompt/schema versions. Success expires after 24 hours; empty results after one hour. Failures are never cached.

`search_usage_reservations` records two SerpApi search units before any provider traffic. Public ceilings are 10 units per UTC day and 180 per rolling 30 days. Session and IP each allow at most three fresh searches per hour; the database stores keyed digests, never their raw values. Venice gets a separate one-call/three-cent reservation immediately before dispatch, capped at five daily and 90 per rolling 30 days. Failures, lost responses, timeouts and restarts never refund allowance. Configuration can lower these positive ceilings; invalid values fail closed.

`search_leases` has one row. A short SQLite write transaction rechecks cache, lease and caps, then grants a random owner token for 75 seconds. SQLite's immediate write transaction serializes competing reservations. Expired leases recover without refunds; old owners cannot release or overwrite a newer lease. Cached responses need neither new allowance nor a lease. No database connection remains held during HTTP work.

## Composition roots and runtime entrypoints

Rails exposes home, health and the CSRF-protected multipart search POST. Puma caps the complete request body at 600,000 bytes before Rails buffering. `SearchesController` establishes the session visitor identity before ActionController::Live starts its stream thread. The flow is synchronous in the same Rails process, without a job service. A disconnect stops later stages and leaves committed allowance counted. Controller and flow ensure stream/upload cleanup. Each deadline owns one active timer per executing thread, so nested calls cannot raise duplicate timeout exceptions during recovery; shorter independent deadlines retain their own timer.

The server budget is at most 55 seconds, including validation and provider calls. Every transport receives the remaining monotonic budget. Progress reports actual started/completed/failed stages; it never estimates percentage or time remaining.

`Dockerfile` pins Ruby 3.4.10 and Node 22.22.3, installs libvips and precompiles the React/Propshaft assets without provider keys. The runtime starts Puma directly with `workers 0` (one process) and at least three request threads. It has no Thruster, frontend server or worker service. `railway.json` defaults to one service replica and `/up` health checks. A real `SECRET_KEY_BASE` is supplied at runtime. Railway checks confirmed a 34.45-second streamed result, a 55.31-second deadline, responsive health checks and mounted records surviving restart and deployment. See [deployment verification](deployment.md).

Production SQLite is pinned by an explicit Rails URL to `/app/storage/production.sqlite3`. `DATABASE_URL` must be absent/empty or exactly `sqlite3:/app/storage/production.sqlite3`; alternative forms, options and external URLs are rejected even when Rails resolves its explicit configuration safely. `ProductionStorage` checks the resolved adapter/path, exact Railway mount environment, canonical directory, actual Linux `/proc/self/mountinfo` entry and real write access. It rejects database/WAL/SHM/journal symlinks. `SearchStore` calls this guard before obtaining its connection pool, so a failed check cannot create an ephemeral SQLite database or reset allowance.

The root entrypoint changes ownership only after verifying the actual mount, then uses `gosu` to drop to the `rails` user. The app user validates storage/configuration before `db:prepare`, preserving the seeded lease on repeat startup. Missing/wrong/unusable storage skips preparation, forces live search off and still starts the upload page, example-photo selection and health route. Submitting the example obeys the same disabled-search outcome as an upload. Failed preparation also disables live search. Startup never substitutes another database or creates a Docker volume implicitly. SQLite and its sidecars stay on the attached `/app/storage` volume. `/up` confirms HTTP responsiveness independently of storage/provider readiness.

`.dockerignore` excludes secrets, databases, Git/private state, tests, tasks/scratch work and historical experiment media from the build context/runtime. The licensed reference image under `app/javascript/search/assets/` is permitted.

Esbuild bundles React, Material UI and Emotion through `jsbundling-rails`. Dependencies/fonts remain local. No frontend server, client router or provider key belongs in browser assets.

## Public response and browser boundary

`POST /searches` accepts multipart `photo` and Rails CSRF. It returns `application/x-ndjson` with `no-store` and streaming headers. Each progress line has `type: stage`, `stage`, `status` and `duration_ms` only after the stage ends. Stage names are `upload`, `lens`, optional `vision`, `ebay` and `filter`. The last line has `type: result` and the `ebay-us-v1` result object.

The result includes `status`, `source` (`live` or `cache`), `marketplace`, `scope`, `retrieved_at`, `query`, `category`, `listings`, `stages`, `query_preparation`, `attempts` and `original_attempts`. Cards contain `id`, `title`, `url`, `thumbnail`, `sponsored`, nullable `price`/`condition`/`shipping` and returned `location`. Price is a supplied `{raw, from, to}` subset; never calculated. Stage details include fixed safe request parameters, response excerpts/counts and measured durations. Lens's phrase remains in its own summary; a Venice phrase belongs to its stage and the final preparation.

A normal fresh search reports `attempts: {uploads: 1, serpapi: 2, vision: 0}`; a fallback adds one vision attempt. Errors report only started attempts. These are attempts, not verified bills. `original_attempts` records the calls behind a saved result. Cache returns the original retrieval time, explanation and durations with zero new attempts. Cache/disabled/busy failures may return only the final line. Skipped Venice appears only in final metadata and never emits a loading event.

Statuses include `success`, `empty`, `disabled`, `busy`, `quota_exceeded`, `visitor_limit`, `vision_limit`, `storage_unavailable`, `configuration_error`, `invalid_photo`, `unclear`, `not_furniture`, `insufficient_time`, `deadline`, `invalid_response` and `provider_unavailable`. Application outcomes use the result status/message; CSRF rejection remains a Rails HTTP error.

The browser uses a 65-second abort and parses bounded NDJSON lines into loading stages and eBay results. Strict session state under `looksalike:ebay-us-v2` accepts only completed live or cache results and restores the current tab after reload without a new search. Invalid state, the old storage key and snapshot results cannot restore in production. The diagram and expandable explanation share the live result metadata. Browser state cannot authorize calls or replace server validation.

Choosing the example prepares the bundled licensed green-sofa reference through the same JPEG preparation as an upload. Find similar items calls the same `submitPhoto` function, streaming actual server progress and preserving normal cache, deadline, cancellation, allowance and error handling. Example and uploaded photos show the same provider/privacy notice. Historical snapshots are not imported by the application entry point.

The standalone mockup alone injects `previewSearch` and enables `preview` on the shared `SearchApp`. Only the explicitly chosen example may return its dated snapshot; other uploads model progress and return a preview-only error. Preview validation may accept `source=snapshot`, saved separately under `looksalike:mockup:ebay-us-v1`. Production protocol validation remains live/cache-only. The historical snapshot and experiment files stay unchanged; remote eBay thumbnails in that preview are unverified and have not been bundled.

## Shared code and testing

Keep concrete Rails/domain names. Do not add a provider framework, repository abstraction, dependency container or component library. Normal tests use explicit offline keys and block live network access. Policy tests use ordinary data; HTTP stubs verify actual parameters, optional-Venice ordering, recognition failures, no retries and sanitization. Real SQLite connections check atomic races, ceilings, expiry/version separation, lease recovery and conservative accounting. Request integration verifies real CSRF and NDJSON outcomes. Browser, hosted and paid quality evidence remain separate.

Run `bin/check` for tests, Rails loading, RuboCop, Biome, Brakeman, audits and the JSX build. Frozen experiment source snapshots are research artifacts excluded from production lint. Preserve historical manifests, source copies, ledger rows and judgments.

## Accepted deviations and historical evidence

- SQLite and one live search keep this demo within one service. Revisit only for multiple instances or measured lock contention.
- Synchronous calls keep the flow small; streaming reports real stages without a background queue.
- Upload-reference expiry does not prove provider-side photo deletion.

The historical manual ledger is `storage/feasibility-v1.sqlite3`, independent of Rails connections. Its CLI rejects external `DATABASE_URL` and non-development environments. Craigslist/location policies and earlier eBay manifests remain historical evidence. The current `docs/experiments/ebay-flow-v6/` comparison passed four of five fixed photos under filter v2/prompt v2; that scoring does not replace request, persistence or browser checks.

# Architecture

## Purpose

This is the boundary contract for LooksAlike's Rails demonstration. A minimal Rails 8.1.3.1 application on Ruby 3.4.10 is implemented; search behavior is still planned. Read this before adding routes, search policy, provider integration, or persistence; update it with the proven search route after the feasibility experiment.

## Current System Shape

The current app has an ERB shell mounting one bundled React/Material UI entry screen, the Rails `/up` health endpoint, and SQLite databases under `storage/`. ZIP entry and local photo preparation/preview work; search and example actions remain disabled until feasibility is proven. Esbuild runs through jsbundling-rails during asset precompilation, with all browser dependencies and system fonts local. Planning documents and the standalone React/Material UI mockup remain separate. Intended runtime: one Rails web service on Railway, with an ERB page shell, a React/Material UI search screen, and SQLite under the mounted `/app/storage` directory. Build browser assets with esbuild through `jsbundling-rails`. Puma runs directly behind Railway HTTPS, with one worker and at least three threads; Thruster is omitted. The app handles one live furniture search at a time and returns up to six normalized listings from one US Craigslist area selected by ZIP code. No separate frontend, worker, or object-storage service is planned.

## Module Map

| Path / entrypoint | Responsibility | May depend on | Must not own |
| --- | --- | --- | --- |
| `app/controllers/searches_controller.rb` / create | Validate request, call search flow, map outcomes to HTTP/UI | Rails, search flow | Provider parsing, ranking, quota policy |
| `app/services/furniture_search.rb` / call | Coordinate upload, queries, normalization, timing, cache, reservations | Injected provider client and store; query/normalizer policy | HTML, browser state, arbitrary URL fetching |
| `app/services/photo_validator.rb` / call; `app/services/search_deadline.rb` / within | Verify bounded image bytes, consume temporary uploads, enforce the shared monotonic time budget | libvips, IO, clock | Provider queries, persistence, browser state |
| `app/services/serp_api/client.rb` / upload, lens, images | Fixed SerpApi endpoints, credentials, remaining-deadline timeouts, retries disabled, provider errors | HTTP library and server configuration | Rails views, ranking, persistence policy |
| `app/models/location_resolver.rb` and bundled location data / resolve | Validate ZIP, resolve representative coordinates, select one approved Craigslist area and canonical Images origin | Plain Ruby, versioned postal data, approved regional centers and overrides | Runtime geocoding calls, user-provided hostnames, listing-distance claims |
| `app/models/search_query.rb` and `listing_normalizer.rb` / call | Small plain-Ruby query extraction, URL filtering, deduplication, ranking | Standard Ruby/data inputs | Network, credentials, ActiveRecord, UI |
| `app/models/search_cache_entry.rb`, `usage_reservation.rb` / store operations | Persist normalized responses, expiry, reservations, and one global live-search lease | ActiveRecord/SQLite, clock | Provider calls inside DB transactions, uploaded image bytes |
| `app/views/searches/`, `app/javascript/search/`, `app/javascript/search/theme.js` | ERB shell, React upload/ZIP/preview flow, Material UI theme and result presentation | React, Material UI/Emotion, public response contract, same-origin Rails requests | API keys, raw provider payloads, authority over validation or quotas |
| `test/` and `docs/experiments/` | Offline contracts and bounded manual live evidence | Public component entrypoints, sanitized fixtures | Automatic billable traffic in normal CI |

Photo validation, shared deadlines, the SerpApi client/HTTP transport, and the plain-Ruby location resolver now exist and are tested offline. `script/import_locations.py` derives the server-only `data/locations/` postal lookup and approved area/origin catalog from explicit public snapshots; the resolver loads the small artifacts once per process. The browser photo module is shared with `script/prepare_photos.mjs`, which freezes output bytes and metadata for later experiment preparation. The remaining search and persistence locations are planned. Keep orchestration in one meaningful flow rather than splitting each step into a pass-through service.

## Dependency Rules

The controller calls the furniture-search flow. That flow resolves location before image upload or quota reservation, then calls the provider edge, policy objects, and persistence. Location resolution, query extraction, and listing normalization stay plain Ruby. The browser receives normalized outcomes, never provider credentials or raw upload IDs. Provider data is untrusted: validate HTTP(S) schemes, the exact selected and approved Craigslist hostname, and individual-listing paths; escape text when rendering.

ZIPs remain five-character strings. Location data uses dated GeoNames postal records and an app-maintained US regional catalog verified against Craigslist's directory, with separately sourced center coordinates and canonical SerpApi origins. Bundle this data on the server, outside browser assets. Explicit overrides take precedence over nearest-center selection; ties use hostname order. This selects an approximate search area, not a listing radius. Unknown or unresolved ZIPs return an error before provider traffic. Cache identity includes ZIP, selected host/origin, and mapping/query versions. Snapshots retain their original ZIP/area and cannot be relabeled for a different input.

The response records ZIP, selected area, route, nullable interpretation, actual parameters, executed stages, timestamps, counts, and attempted searches. Lens-only preserves provider order and does not require an inferred phrase. The two-search route uses the frozen extractor and deterministic keyword ordering. Listing links come from each result's `link`, not image fields. The probe freezes location mapping and five photo/ZIP pairs along with these rules before scoring, and keeps a pre-call attempt ledger independently of production accounting.

## Composition Roots And Runtime Entrypoints

Rails routes expose the home page, search POST, curated example, and health check. `FurnitureSearch` accepts injected provider/store collaborators with production defaults in the Rails wiring. Puma handles requests synchronously under one absolute deadline. CLI evidence recording is manual and separate from CI. Startup verifies the intended writable volume and prepares SQLite after mount; it cannot silently substitute ephemeral storage. The first deployment serves the genuine bundled snapshot with live calls disabled; timing stubs are removed/disabled before public live use.

The page mounts one React root; React owns the interactive screen and lifecycle cleanup for selected images and requests. Submit same-origin requests with Rails CSRF protection. Esbuild bundles React, Material UI, and Emotion during Rails asset preparation; the Railway build includes Node and npm. No client router or frontend server is needed. The standalone mockup build stays under `tasks/mockup/` and does not call the backend.

React also saves the completed view in browser session storage: normalized results, ZIP/area, original retrieval date and result source, sanitized search details, a small reference thumbnail, and explanation state. Reload restores this view without another search. “Search again” clears it; unavailable or corrupt storage falls back to the upload screen. Original uploaded files and provider IDs are excluded. This client state cannot authorize requests or replace server validation, cache, or quotas. The explanation's diagram and details reflect the recorded route and counts.

## Shared Code Rules

Use Rails conventions and small domain names. Introduce a shared helper only for multiple actual consumers. Use Material UI components with one shared theme for colors, typography, and control states; avoid parallel custom input/button implementations. No general integration framework, generic repository abstraction, dependency container, or bespoke component library is needed.

## Testing Boundaries

Test pure location/query/normalizer behavior with small inputs; include leading-zero and unresolved ZIPs, rural and boundary cases, known overrides, state/DC coverage, Alaska/Hawaii, and audited territory coverage. Test the provider boundary with recorded sanitized JSON and HTTP stubs, including actual call count after transport failures and rejection of other regional hosts. Request integration exercises the real flow with a stubbed provider. Persistence tests exercise atomic caps, global lease ownership/expiry, conservative accounting, and cache separation after location changes. Verify two different uploads do not delay the example or health endpoint. Browser verification covers the user journey, ZIP editing, errors, layout, announcements, and fully bundled snapshot imagery with external requests blocked. Live quality/latency tests are manual, budgeted evidence and cannot be replaced by successful fixtures.

## Architecture Checks

Run `bin/check` for Rails loading checks, Minitest, RuboCop, Biome, Brakeman, dependency audits, and the JSX bundle build. GitHub Actions invokes the same command; production asset compilation remains a deployment build check. Review that only the provider client makes SerpApi network calls and that policy classes do not acquire IO dependencies. Verify Material UI keyboard focus and error states in the browser. No custom architecture-check framework is planned.

## Accepted Deviations

- September 10, 2026: SQLite for operational cache/quota state avoids another service for a single-instance demo; revisit only if multiple instances or measured lock contention require it.
- September 10, 2026: synchronous search keeps the app small. Revisit only if the measured route cannot reliably finish within the chosen host/request budget; do not introduce a background queue just to animate stages.
- Uploaded photos are transient server request data and are never stored in the server database. The browser keeps only a small reference thumbnail for the current tab's reload behavior and clears it with “Search again.” Example fixtures bundle deliberately selected reference/result imagery with provenance and a documented reuse basis. Temporary upload-ID expiry does not prove provider-side deletion.

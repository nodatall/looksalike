# LooksAlike visual search demo

Goal: Build a small app that turns a furniture photo into up to six similar eBay listings located in the United States.

The app will search nationwide eBay listings from a photo, without a ZIP or typed description. The [five-photo comparison](../docs/experiments/ebay-flow-v3/README.md) passed four cases. The [focused ornate-sofa retest](../docs/experiments/ebay-flow-v4/README.md), after tightening the Venice trigger and filtering listing types, found four relevant items out of six in 12.8 seconds. Two were close matches and two shared mainly pattern or style. Recheck all five photos under the changed rules before release. The example data is prepared; permission to bundle listing photos remains unverified.

Deliver implementation instruction:
When asked to implement this doc, load the `$deliver` skill, use this file as the approved execution plan, scan every checkbox, and continue through final review, archive movement, commit, and finalization before the final handoff.

## What we are building

The first screen starts with “Find similar furniture on eBay.” It has a photo upload box and no ZIP field. The box shows a photo icon and “Upload a furniture photo,” with “or try an example” underneath. Only “example” is clickable.

Uploading, dropping a photo, or choosing the example fills the same box with a preview. The headline stays in place. “Find similar items” appears below the preview and stays disabled until a valid photo is ready. The preview remains clickable to replace the photo.

Submitting shows a loading animation inside the button and keeps the photo visible. Results use this layout:

- A small reference photo beside the one-line heading “Similar Items.” Omit “Near [ZIP].”
- “Search again” at the top right. It clears the photo and results and returns to the upload screen.
- Up to six cards in three columns on desktop and two on narrow screens. Each shows a photo, title, price when supplied, and eBay listing link. Show supplied shipping, pickup, condition, and location details when available. Do not invent a city or imply that a pickup item is nearby.
- A collapsed “How this search worked” section below the cards. It starts with the black-on-white architecture sketch, then explains each call and its response in short text.

Keep the copy as spare as the mockup. Omit a reference-photo caption, result-count subtitle, and an introduction above the diagram. Mark saved results with a short status and retrieval date, as described below.

Reloading a completed search restores the results, reference thumbnail, and whether the explanation was open. It does not upload again or start another search. This lasts for the browser tab's session; it is not a saved-search feature.

The app covers furniture on eBay located in the US. It has one screen, with no accounts, saved searches, alerts, price or distance filters, pagination, or listing-detail pages. Use SerpApi for Lens and eBay search. Use Venice only to describe the photo when Lens lacks detail. Keep listing selection deterministic and do not scrape marketplace pages in the app.

Search ebay.com without the provider country filter, then keep only listings explicitly marked as located in the United States. Do not send a ZIP, select a Craigslist area, or restrict results to local pickup. US location does not guarantee delivery to every US address. Visitors check shipping and pickup terms on eBay.

Visual mockup: [Earlier screen](ui-mockup-looksalike-demo.html). Updating it for nationwide eBay is pending.

## Project choices

| Choice | What it means |
| --- | --- |
| Rails | One app serves the page, handles searches, and calls SerpApi and the optional vision fallback. |
| React and Material UI | React handles the interactive screen. Material UI supplies inputs, buttons, loading indicators, and cards, with one shared theme and consistent keyboard focus styles. |
| Railway | One service hosts the public demo over HTTPS. |
| SQLite | A small database stores recent search results and usage counts. It does not store uploaded photos. |
| Public GitHub repository | Anyone can read the source and setup instructions. |

The repository contains this plan, the earlier interactive mockup, and a working Rails foundation. The bundled React/Material UI entry screen is connected to Rails. SerpApi credentials are configured locally. Updating the app and mockup to nationwide eBay is pending; the remaining search experience and deployment depend on validating the new flow.

## Limits visitors will see

| Limit | Behavior |
| --- | --- |
| Location | Search for US-located eBay items without asking for a ZIP. Do not promise nearby pickup or delivery eligibility. |
| Photo size | Accept one JPEG, PNG, or WebP, up to 10 MB and 20 megapixels. Reduce it to at most 450,000 bytes before sending it. |
| Results | Show up to six distinct listings. Fewer results are acceptable. |
| Waiting time | Stop the server's work after 55 seconds. Give the browser 65 seconds to receive and show the outcome. |
| Simultaneous searches | Run one live search at a time. Another visitor gets a prompt “busy” message; the example and saved recent results remain available. |
| Public API allowance | Allow at most 10 search attempts per day and 180 in any rolling 30 days. |
| Per-visitor limit | Allow three searches per hour that need fresh results, tracked by browser session/IP address. |
| Repeated photos | Reuse a successful result for 24 hours, or an empty result for one hour, using the same search version and US scope. Show when it was retrieved. |
| Prepared example | Show a dated “Demo snapshot” that uses no API searches and works even when outside services are unavailable. |

A search attempt counts against the limit even if its outcome is uncertain. The app will not retry paid searches automatically. Development experiments and public searches share the account's allowance.

The server keeps uploaded photos only while handling the request. The browser retains a small reference thumbnail in this tab so results survive a reload; “Search again” clears it. Before upload, tell visitors that the reduced photo goes to SerpApi/Google and, when needed, Venice for image recognition. Keep both API keys on the server. Use the selected private Venice model and request `store: false`; describe provider handling according to its published policy. Search results may include expired listings, so the app must not claim that an item is still available.

## Steps

### 1. Set up the repository and a working Rails app

- [x] Initialize Git with a `main` branch and a `deliver/looksalike-demo` working branch. Save the reviewed planning files as the starting point.
- [x] Install a supported Ruby version, create the Rails app, and confirm it runs locally.
- [x] Add React and Material UI to the Rails-served page, with a JavaScript build that runs locally and during deployment.
- [x] Add setup instructions, an example configuration without secrets, and rules that keep private files out of Git.
- [x] Add one command for the automated code, security, and test checks, with GitHub Actions configured to run it. Verify the hosted run after publishing the repository.

### 2. Check whether the search idea works

The Craigslist comparison below is historical. Preserve its rules and completed tasks. The pending tasks that follow cover the approved nationwide eBay direction.

Test five fixed photo/ZIP pairs: an ornate sofa in 10001, a modern sofa in 94103, a dining chair in 60601, a wood table in 02108, and a dresser in 98101. Use photos we own or have permission to reuse. Each photo is tested in its assigned area, keeping this comparison to five cases per approach.

Try Google Lens alone first, restricted to the Craigslist area selected by the ZIP code. If that fails, try Lens to produce a search phrase, followed by Google Images in that area. Each approach also needs a separate image-upload request.

**An approach passes when at least four of the five cases each return three relevant, distinct, accessible listings from the selected Craigslist area among the first six results, within 55 seconds.** Relevant means the same furniture category with a similar shape, material, or style. Check the listings by hand, but do not replace poor results to improve the score.

Spend at most **15 search attempts** on this comparison: up to five for Lens alone, then up to ten for the two-search approach. Stop testing an approach after two photos fail, because it can no longer pass. Keep up to **two additional attempts** for a final deployment check with a new photo, subject to the account and public limits.

- [x] Build and test the photo compression and API request code without paid calls. Include the 55-second deadline and disable automatic retries.
- [x] Build and verify the offline ZIP-to-area lookup, including leading-zero ZIPs and a clear outcome for ZIPs that cannot be located.
- [x] Save the five prepared photo/ZIP pairs, selected areas, and exact search rules before testing, so the results can be judged consistently.
- [x] Add a search-attempt counter that survives restarts and counts each request before it is sent.
- [x] Run the comparison within its budget and save the results, timings, and reasons for each pass or failure.
- [x] Run the approved two-request diagnostic with the two saved Images queries. Record response classifications and reasons for rejected links, keep the original scores, and stop at eight combined search attempts.
- [x] Build the approved simpler query rule and test the two recorded sofa phrases with two Images requests. Keep the area and listing checks unchanged, preserve earlier evidence, and stop at ten combined search attempts.
- [x] Run the approved two-request eBay trial with the saved sofa phrases, ZIPs, and pickup filter. Record its parameter rejection and useful antique-sofa results, preserve earlier evidence, and stop at twelve combined attempts. This trial does not authorize switching the app or establish a full-route pass.
- [x] Complete the approved single nationwide eBay test with `green velvet sofa`, US country filtering, and no ZIP or pickup-only restriction. It timed out at 55 seconds. Stop at thirteen combined attempts.
- [x] Retry that exact request once with a 110-second diagnostic deadline. It returned HTTP 503 after 90.34 seconds, matching the original request's archived provider failure. Stop at fourteen combined attempts; keep the application's 55-second target unchanged.
- [x] Run the approved test removing only `_salic=1`. It returned 60 listings in 2.12 seconds; 59 were explicitly US-located. Stop at fifteen combined attempts. This is a query test, not a full-flow or similarity pass.
- [x] Freeze and run the five-photo Lens-to-eBay comparison, omitting the provider country filter and checking US location locally. Two sofas passed; the chair and coffee table failed. Stop after eight searches and four uploads, leaving the dresser untested.
- [x] Repair phrase extraction using the approved voting rule and check saved Lens results without paid calls. Both sofa phrases stay unchanged; the chair and coffee table now keep the correct type.
- [x] Run the fresh five-photo comparison with the revised rule. Stop after two failures: the ornate sofa and chair failed, the modern sofa passed, and the remaining photos were not run. Use six searches and three uploads; preserve the original scores.
- [x] Add the photo fallback and verify its trigger, output checks, timeout, and errors without paid calls. Visitors never need to type a description.
- [x] Verify the provider switch to Venice, including its image request and structured-response handling, without paid calls.
- [x] Configure Venice and test the same five photos. Four passed; the ornate sofa failed. Use three vision calls, ten SerpApi searches and five uploads, with no retries.
- [x] Pass the existing four-of-five quality requirement before building the remaining app. Keep the earlier reports and scores unchanged.
- [x] Ask Venice when Lens has only a broad style description, such as “vintage sofa,” instead of a concrete color or material detail. Keep the same model and call limits.
- [x] Filter out wrong furniture types and accessories before taking the first six eBay listings. Apply the same checks to promoted items, and keep the remaining provider order.
- [x] Retest the ornate sofa once with the revised rules: at most two SerpApi searches, one upload and one Venice call, within 55 seconds. Record the original and filtered lists and review every displayed item. Keep earlier scores unchanged; this focused test does not revalidate all five photos.
- [ ] Recheck the five fixed photos under the revised fallback and listing rules before release. The one-photo retest does not establish a new five-photo score.
- [ ] Package the [prepared modern-sofa example](../docs/examples/modern-sofa-2026-09-28.json), including its reference photo and actual listing thumbnails with permission to reuse them. The saved data is ready; listing-image permission and bundled assets are still needed.

The preceding Craigslist comparison is historical. Its frozen inputs, two-failure stop rule, budget, scores, and completed tasks remain unchanged. The user has approved replacing that direction with nationwide eBay. For the new full-flow comparison, require at least four of five photos to return three relevant, distinct, accessible US-located listings among the first six, within 55 seconds. Stop after two failed photos. Record short-phrase probes separately; they cannot establish a full-flow pass.

**If the new approach fails, stop feature work and return the evidence and smallest proposed change.** Do not increase the approved live-call allowance or use the example to claim that live uploads work. If we cannot obtain reusable listing images, flag that before promising a complete example.

The first comparison used six search attempts and four uploads. Both approaches stopped after two failed cases, leaving three photos untested on each. The two-call diagnostic brought usage to eight attempts and confirmed that the modern query returned links outside Craigslist. The original scores and frozen rules remain unchanged.

The approved [short-query test](../docs/experiments/query-v2/README.md) used two more Images attempts with saved descriptions and the same area restrictions. San Francisco produced no accepted listings. New York produced two candidates, but neither matched the reference. This does not replace the five-case comparison.

The approved [eBay trial](../docs/experiments/ebay-v1/README.md) used two more attempts. The green-sofa request was rejected because the API did not accept the documented `LH_PrefLoc=Domestic` value. Removing that optional parameter for the antique-sofa request returned 60 listings in 2.52 seconds. Three of the first six looked similar to the reference, and all six pages showed New York pickup locations. The API itself supplied only country-level locations. That trial did not test fresh Lens recognition or the remaining photos; the later full-flow comparison is recorded separately.

The approved [nationwide test](../docs/experiments/ebay-us-v1/README.md) used one further attempt for `green velvet sofa` with `_salic=1`, no ZIP, and no pickup-only filter. It timed out after 55.01 seconds without a completed response. This is inconclusive about inventory, similarity, and country filtering; it is not an empty result or a full-flow pass.

The original request's [archived response](../docs/experiments/ebay-us-v1/archive-diagnosis.json) later confirmed HTTP 503 after 90.11 seconds. The user-approved [identical retry](../docs/experiments/ebay-us-retry-v1/README.md), with a longer diagnostic deadline, also returned HTTP 503 after 90.34 seconds. This nationwide request has now failed twice; the provider's generic error does not identify the cause. Increasing the app deadline would not resolve these failures.

The user-approved [test without the country filter](../docs/experiments/ebay-no-country-v1/README.md) then returned HTTP 200 and 60 listings in 2.12 seconds. All other request parameters were unchanged. The country filter is therefore the likely source of the failures, although the provider's internal cause is unknown. The response marked 59 listings US-located and one Philippines-located. The implementation will omit `_salic` and check the returned location locally; no application code changed in this test. The first six included four sponsored items, and visual relevance remains unreviewed.

Earlier experiments used **23 search attempts** before the repaired comparison. On September 25, 2026, the fresh account check confirmed 230 searches remaining. The new batch used six searches and three uploads, bringing recorded development usage to **29 search attempts**. The remaining account balance was not refreshed for that batch. It stopped after two failures; unused allowance could not bypass that stop. Further focused diagnostic batches are authorized within the remaining account allowance, but must record their purpose and size before dispatch. Preserve every earlier attempt and frozen score, and keep the separate two-search deployment check reserved.

The September 28 [Venice comparison](../docs/experiments/ebay-flow-v3/README.md) used ten more searches and five uploads, plus three vision calls. Four of five photos passed within 19 seconds. Recorded development usage is now **39 search attempts**; the post-run account check confirmed **214 searches remaining**. The two-search deployment reserve is untouched. The modern-sofa example data is prepared, but the listing photos still need documented reuse permission before bundling.

### 3. Put the example online first

This checks the hosting setup before we expose paid searches to visitors.

- [ ] Create the public GitHub repository and publish the checked starting version.
- [ ] Deploy the example to Railway with live search switched off.
- [ ] Verify that the database is writable and that its records survive a restart and a new deployment.
- [ ] Use a temporary simulated search to check that Railway permits responses beyond 30 seconds and that the app stops work at its 55-second deadline.
- [ ] Remove or disable that temporary test route before allowing public live searches.

### 4. Build the complete visitor experience

Use the same compression and search rules that passed the experiment.

- [ ] Update the mockup and app to the photo-only upload, example, and preview flow above, with compression and clear file errors.
- [ ] Remove ZIP entry, ZIP validation, area lookup, and nearby wording from the active flow. Enable search once a valid photo is ready.
- [ ] Connect uploads to the chosen search approach and return up to six valid, distinct listing cards.
- [ ] Store recent results by photo, US scope, and search version, and show their age when reused.
- [ ] Enforce the spending limits and one-live-search rule, including during simultaneous requests and restarts.
- [ ] Build the results header and responsive cards described above using Material UI and the shared theme.
- [ ] Restore completed results after a reload in the same tab, without new API calls. Clear that saved view on “Search again.”
- [ ] Add understandable loading, empty-result, timeout, busy, and usage-limit messages. Keep the photo visible after an error and offer the example as another action.
- [ ] Add the architecture sketch and concise call-by-call explanation. Show the actual route, useful inputs and responses, and local processing. Count uploads separately from searches, and distinguish new calls from saved details.

### 5. Check the app before release

- [ ] Test the search rules, upload checks, errors, saved results, and spending controls using recorded responses instead of paid API calls.
- [ ] Verify that requests omit the provider country filter and that local filtering rejects candidates whose US location cannot be established. Check that cache and browser-storage versions cannot restore old Craigslist or ZIP-based results as eBay results.
- [ ] Verify that simultaneous requests cannot exceed the limits and that the example and health check still respond during a live search.
- [ ] Verify that every image in the prepared example loads with external image and API requests blocked.
- [ ] Walk through uploads, the example, errors, and retries on desktop and mobile, including keyboard-only use.
- [ ] Check photo-based button enablement and the inline example preview. Verify that reload restores results without a provider call and that “Search again” clears them.
- [ ] Run all automated checks and inspect the public files for secrets, private photos, and misleading claims.
- [ ] Capture screenshots and a short walkthrough recording.

### 6. Enable live search and share the demo

- [ ] Deploy the checked app and enable live searches with the spending controls in place.
- [ ] Confirm that one previously unseen photo works on the public site within the reserved two-attempt budget and 55-second deadline.
- [ ] Confirm that the example, error messages, listing links, and usage records still work after a restart or deployment.
- [ ] Finish the README with the public demo and source links, setup instructions, an architecture diagram, API costs, known limits, and one concrete troubleshooting finding.
- [ ] Complete final review and publish the demo link.

If search quality, request timing, or storage fails these checks, fix it or return to the stop condition in step 2 before calling the demo ready.

## What “ready” means

The public HTTPS link works without login. Visitors can try the complete example or upload a new photo without a ZIP. The US listing checks, five-photo comparison with the photo fallback, and final new-photo check have passed.

The page matches the mockup on desktop and mobile and works with a keyboard. A completed search survives a reload without repeating API calls. Errors explain what happened and offer a useful next action. Recent results and historical examples are labeled clearly.

Automated checks pass without paid searches. The database survives deployment changes. The public source, README, and recording explain how the app works and its limits.

## Technical appendix

These details preserve the implementation decisions. The steps above should be understandable without this appendix.

### Rails and Railway setup

Rails 8.1.3.1 and Ruby 3.4.10 are pinned for this app. Use the installed Homebrew Ruby without changing macOS system Ruby. GitHub and Railway sign-in have been verified; deployment remains a later step.

Use ERB for the page shell and mount one React root for the search screen. Material UI and its default Emotion styling engine provide the controls and theme. Use Rails `jsbundling-rails` with esbuild to compile JSX and bundle pinned npm dependencies during asset preparation. Keep React/Material UI versions compatible and commit the lockfile. There is no separate frontend service, client-side router, or React server rendering. [Material UI setup](https://mui.com/material-ui/getting-started/installation/), [Rails JavaScript bundling](https://github.com/rails/jsbundling-rails)

React owns browser interactions and sends requests to same-origin Rails endpoints with Rails CSRF protection. Rails owns validation, credentials, search rules, cache, and quotas. Use Minitest, RuboCop, Brakeman, the JavaScript build, and GitHub Actions for normal checks. Bundle UI dependencies locally so the example has no CDN or font-service dependency.

The mockup source is `tasks/mockup/main.jsx`; its build command is documented in `tasks/mockup/README.md`. The generated HTML remains self-contained for direct viewing. Use Material UI's outlined inputs and theme focus states; avoid global focus rules that draw extra rings around inputs or headings. Keyboard focus and validation errors must remain visible.

Run Puma directly behind Railway's HTTPS service, with one worker and at least three request threads. Omit Thruster from the generated start command because its default timeout conflicts with the planned request length. Mount all production SQLite files at `/app/storage`. Set writable ownership for the app user and prepare the database at startup, after the volume is mounted.

Use a cheap health endpoint. If the intended database volume is missing or unavailable, disable live calls instead of creating a temporary replacement database. Keep the shared component boundaries in [ARCHITECTURE.md](../docs/ARCHITECTURE.md).

### Nationwide eBay search

The active flow has no ZIP lookup, geocoding, or Craigslist-area selection. Keep the old location data and code only where historical experiments need them; do not call them from the new search.

Use Google Lens with `type=all` to obtain suggestions and visual-match titles. Treat these as possible search terms, not guaranteed descriptions. [Lens API](https://serpapi.com/google-lens-api)

Approved phrase extraction repair:

1. Read the first eight Lens result titles. Each title gives at most one vote to each recognized furniture type. Normalize names such as “couch” to “sofa.”
2. Recognize complete types such as “coffee table” before matching their generic word “table.” A matched compound does not also vote for its generic word.
3. Choose the unique type with the most votes, only if at least two titles support it. A tie or too little evidence returns weak recognition to the fallback decision below. Related suggestions cannot bypass this rule.
4. Keep at most two familiar traits repeated in the titles supporting the selected type. Keep the existing trait order and synonym rules. Do not add another search to rescue a weak result.

The completed query-v3 comparison remains frozen. The next comparison uses this Lens policy plus the photo fallback below, with a new manifest and separate attempt records. Keep the same photos, provider ordering, US-location checks, 55-second deadline, quality threshold, and two-failure stop.

Pass the phrase as `_nkw` to `engine=ebay`, with `ebay_domain=ebay.com`. Omit `_salic`, `_stpos`, `show_only=LPickup`, and `LH_PrefLoc=Domestic`. The country-filtered request failed twice; removing only `_salic` succeeded. Enforce US location using the returned listing fields below. [Observed request comparison](../docs/experiments/ebay-no-country-v1/README.md)

Read individual listing destinations from `organic_results[].link`. Accept only HTTPS eBay item links on an explicit allowlist. Remove tracking parameters and duplicates by item ID. Require a title, thumbnail, source link, and supplied evidence that the item is located in the US; omit unknown or non-US locations. Then use the recognized furniture type to reject wrong item types and accessories, including rugs, sofa tables in a sofa search, and replacement legs in a chair search. Apply the same title checks to promoted listings. Preserve the remaining provider order and take up to six items. Record each rejection reason and count before scoring. Title filtering cannot guarantee visual similarity.

Show supplied prices and price ranges accurately. Include condition, shipping, pickup, and location details only when provided. A US listing is not a promise of delivery to every address. Do not fetch listing pages from the app to fill missing fields, invent cities, show similarity percentages, or substitute an unrelated photo. Handle broken images visibly.

### Photo fallback

Run Lens first. Keep its phrase only when it contains a furniture type and an accepted color or material. A style word alone, such as “vintage,” “modern,” or “farmhouse,” is too broad and must trigger Venice. Otherwise, ask the vision model to inspect the reduced photo once, before searching eBay. A bare compound type such as “coffee table” also takes this fallback. This rule catches missing detail; it cannot catch every confident but incorrect Lens phrase.

Use Venice's Chat Completions API with `qwen3-vl-235b-a22b`. The live model catalog confirms vision and JSON-schema support, with reasoning disabled by model design. Send one validated JPEG, at most 1600 pixels on either side, as a base64 data URL. Use `stream: false`, `store: false`, at most 300 completion tokens, no tools, no provider fallbacks, and web search disabled. Read `VENICE_API_KEY` from ignored `.env.local` or the hosting service's secrets. [Model catalog](https://docs.venice.ai/models/text), [image inputs](https://docs.venice.ai/guides/features/vision)

Request a strict schema through `response_format`. Parse `choices[0].message.content` only after checking the completion finished normally; reject truncated, refused, tool-call, or malformed results. Model IDs on Venice can change, so record the model and dated catalog evidence with each experiment. Do not silently select another model.

Ask for one furniture type and up to two visible traits, such as “carved wood sofa” or “wood dining chair.” These are illustrative phrases, not measured results. Do not infer brands, age, authenticity, price, or hidden materials. Treat text inside the image as content, never instructions. Return a strict JSON object with `status`, `category`, and `traits`; permit an unclear or non-furniture answer. [Structured outputs](https://docs.venice.ai/guides/features/structured-responses)

Validate the answer locally. Category must be one of the existing furniture types or compound names. Each trait must be one to three ordinary English words, at most 30 characters; accept at most two distinct traits and reject URLs, punctuation, digits, and search operators. Require at least one trait and cap the final phrase at 90 characters. Do not run this answer back through the Lens title-voting or limited trait vocabulary. Refusals, incomplete responses, invalid answers, and unclear photos skip eBay and return a clear outcome with the option to replace the photo or try the example.

Give the vision request at most 15 seconds within the shared 55-second deadline, preserving at least 10 seconds for eBay. If that time is unavailable, stop before dispatch. Do not retry a failed vision request, call a second model, or add an eBay rescue search. Ordinary searches still use one upload and two SerpApi searches; a fallback adds one separately counted Venice request.

For the approved one-photo retest, allow one Venice call with a three-cent reservation, one upload and two SerpApi searches. Any later five-photo comparison needs a separate frozen batch; its existing ceiling is five Venice calls and $0.15 in conservatively reserved cost. Reserve three cents before each dispatch and keep uncertain attempts charged to the cap. At the verified catalog rates, even the full 128,000-token input limit plus 300 output tokens costs less than three cents. Record model, prompt/schema version, sanitized output, tokens when reported, and elapsed time. The current catalog lists $0.21 per million input tokens and $1.90 per million output tokens; recheck those rates before the batch. Measure returned usage before publishing a per-search estimate. [Pricing and capabilities](https://docs.venice.ai/models/text)

Before public use, enforce separate vision limits of five calls daily and 90 in a rolling 30 days, with the same no-retry rule. Cache identity includes the trigger policy, provider/model, prompt/schema, and phrase-validation versions. Cached results and the prepared example make no vision calls. API credentials, photo bytes, and raw provider payloads never appear in the explanation or logs.

### Experiment records

Before the new scored comparison, save the compressed image bytes and hashes, compression settings, local US-location rule, request parameters, phrase rules, URL filters, duplicate rules, and result ordering in a new manifest. Verify compression, normalization, spending controls, and request deadlines offline first. Keep the earlier Craigslist manifests and ZIP assignments unchanged as historical records.

Check the account's remaining allowance before starting. The manual experiment uses its own durable counter from the first request, separate from the public app's daily limit. Its step 2 budget applies cumulatively across restarts.

Record sanitized responses, timings, phrase quality, card counts, missing fields, inaccessible links, relevance judgments, and timestamps under `docs/experiments/`. When the early-stop rule applies, mark the remaining photos untested. Do not add custom rescue queries.

Changing the algorithm invalidates the affected scores. Extra tuning uses the approved remaining monthly allowance in recorded, bounded batches; request a new budget only if that allowance would be exceeded. The sample demonstrates this small test only; it does not establish general accuracy.

### Uploads and privacy

Rails independently checks the bytes, format, dimensions, and size against the photo limits above before contacting SerpApi. Show an actionable error if browser compression cannot meet the limit.

SerpApi's Image API accepts these formats up to 500 KB. Its `image_id` expires after ten minutes, so a new uncached search uploads the reduced image again. ID expiry does not prove that the provider has deleted the image. [Image API](https://serpapi.com/image-api)

Clean temporary upload files on success and failure. Do not accept arbitrary image URLs or fetch user-supplied URLs from the server. Remove keys, upload bodies, provider upload IDs, and credential-bearing URLs from logs and recorded test data.

### Saved results and the prepared example

Use browser session storage to restore a completed view: normalized cards, marketplace and US scope, retrieval date, live/cache/snapshot status, sanitized search details, a small reference thumbnail, and the explanation's open state. Keep the upload's original bytes and provider upload ID out of this storage. Restore the previous result as-is, including its date; refreshing must never resubmit the search. An unfinished search is not a completed result and must not restart automatically.

Validate restored data and handle unavailable or corrupt storage by returning to the usable upload screen. “Search again” clears the saved result and thumbnail. Change the storage version so old Craigslist or ZIP-based views cannot be restored as eBay searches. This browser copy is separate from the server cache and must never authorize calls or bypass limits.

For the saved results in step 4, use a cache key built from the reduced image's SHA-256 hash, eBay marketplace, local US-location rule, and search/query version. Keep the original retrieval time and search details. Label a reused response “Cached.”

Apply the expiry times in the limits table. Provider failures must not be stored as successful results.

Save the example as a sanitized response snapshot in the repository. Record the image sources and reuse permission alongside the bundled files. Do not substitute unrelated stock images. Show its label immediately, retain historical listing links, and mark availability unverified. Never use it as the response to an unrelated upload.

Choosing the example fills the existing upload screen and never submits immediately. “Find similar items” then loads the prepared nationwide eBay snapshot with its original retrieval date and search details. It spends no API allowance and needs no artificial wait.

The earlier mockup uses the selected purple Victorian couch and illustrated Craigslist results. Update its copy, cards, controls, saved state, and diagram together for eBay. Public release needs permission to reuse the reference photo or a suitable replacement, plus a genuine recorded eBay result. Keep source and reuse notes in the mockup README.

### Spending and simultaneous requests

Make the public limits configurable. They are ceilings, not a claim about the account's remaining balance. The referenced free plan allows 250 searches per month; recheck the shared account before enabling live traffic. [Pricing](https://serpapi.com/pricing)

Before calling SerpApi, reserve enough allowance for the chosen approach's maximum search cost in one database transaction. Keep those reservations across restarts. Do not release reserved allowance when an in-flight request's outcome is uncertain.

Enforce the one-live-search rule through a persisted lock, called a lease. Reject another uncached request before uploading or reserving its search allowance. The lease must last longer than the server deadline plus cleanup time. Recover expired leases without refunding uncertain spend.

Reused results spend no provider allowance. The health endpoint must remain responsive alongside those results and the example.

### Deadlines, progress, and errors

The server deadline covers validation, upload, image recognition, and all search calls together. Measure elapsed time with a monotonic clock so clock adjustments cannot extend it. Each network operation receives only the remaining time. Set `Net::HTTP#max_retries = 0` if using that client.

A browser disconnect does not guarantee that the provider stopped work. Do not automatically switch search approaches after a failure.

Use the shared API client for step 3's simulated search. Run its timing checks in both the production container and Railway.

Show one animated loading state. Display completed stages and their durations only when they actually finish. Do not claim progress based on a timer.

Give weak recognition, missing metadata/images, and provider errors their own outcomes alongside the states listed in step 4.

### How the search explanation works

Start with a black-on-white architecture sketch showing the browser, Rails, SerpApi Image, Google Lens, the optional Venice photo fallback, and eBay search. Use sketch-style boxes and labeled arrows, with solid requests and dashed responses. Number only provider calls. Remove the local ZIP/area files and Google Images stage.

Visitors follow one flow: upload, Lens, optional photo fallback, eBay, and listing selection. A fresh successful search uses one SerpApi upload and two SerpApi searches, plus one Venice request only when needed. Saved results make no new calls.

Begin with the browser's photo request to Rails, then show:

1. **Upload the photo.** Show the reduced format and size, upload endpoint, and a safe response summary. Explain that the returned reference becomes the input to Lens. Do not expose the upload ID or image bytes.
2. **Search with Google Lens.** Show useful response excerpts and the short phrase they produced. Phrase extraction is local work, not another API call.
3. **Describe the photo, when needed.** Show why Lens needed help, the model name, and the short phrase returned. Omit the photo payload. When unused, show this stage as skipped.
4. **Search eBay.** Show the phrase, ebay.com marketplace, and response excerpts used for listing cards. Explain the US-location check in the next step. There is no ZIP or pickup-only filter.
5. **Choose the displayed listings.** Show counts before and after URL, US-location, duplicate, and missing-field checks. This is local processing.

For each external call, show its outcome and measured duration when available. Keep request details sanitized and response excerpts short. Mark failed or skipped stages honestly. Show the retrieval time separately from listing dates; search-attempt counts are not verified bills.

The local mockup uses completed-search wording to preview the finished design. Its README records that the requests, responses, and counts are modeled; they are not evidence of working API calls. In the live app, cached results and the prepared snapshot show zero new calls, with the original calls, counts, timings, and retrieval date shown separately when recorded. Never present saved or modeled details as a live search that just ran.

### Verification and documentation

The offline checks in step 5 cover extraction, listing URLs, duplicates, missing metadata, errors, cache expiry, and usage accounting. Include browser and server upload limits, actual request counts after network failure, lease recovery, and simultaneous different uploads.

Add one request-level integration flow. The browser walkthrough also checks focus, error announcements, broken images, double submission, and timeout recovery. Check reload after an upload and after the example, including open and closed explanations, unavailable storage, legacy Craigslist state, and an interrupted search. Restoring a completed view must make zero upload or search calls.

Check the explanation for the Lens-to-eBay flow, failures, cached results, and the example. Each call must show how its response feeds the next step; local work must not increase the upload, search, or vision-call counts.

Add instructions to refresh recorded responses, experiment results, and the recording to the README contents listed in step 6.

The completed [Pro analysis](tmp/pro-analysis-looksalike-demo.md) records the earlier technical review and seven adopted findings. It predates the nationwide eBay decision and several UI changes; it does not validate the new flow. The current direction is approved, but implementation and release still require the checks above.

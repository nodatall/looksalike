# LooksAlike visual search demo

Goal: Build a small app that turns a furniture photo and a US ZIP code into up to six similar listings from a local Craigslist area.

Please review this before I start.
Tell me what is wrong, missing, or out of order.

Deliver implementation instruction:
When asked to implement this doc, load the `$deliver` skill, use this file as the approved execution plan, scan every checkbox, and continue through final review, archive movement, commit, and finalization before the final handoff.

## What we are building

The first screen starts with “Find similar items on Craigslist near you.” It has an outlined “ZIP code” field with no asterisk, followed by a photo upload box. The box shows a photo icon and “Upload a furniture photo,” with “or try an example” underneath. Only “example” is clickable.

Uploading, dropping a photo, or choosing the example fills the same box with a preview. The headline and editable ZIP stay in place. Choosing the example fills an empty ZIP with the example's ZIP and preserves any ZIP already entered. “Find similar items” appears below the preview and stays disabled until a photo and five-digit ZIP are present. The preview remains clickable to replace the photo.

Submitting shows a loading animation inside the button and keeps the photo visible. Results use this layout:

- A small reference photo beside the one-line heading “Similar Items,” with “Near [ZIP]” directly underneath.
- “Search again” at the top right. It clears the photo and results, returns to the upload screen, and keeps the ZIP available to edit.
- Up to six cards in three columns on desktop and two on narrow screens. Each shows a photo, title, location, and listing link. Show a price only when supplied. Use a supplied city or neighborhood; otherwise label the broader location “Craigslist area: [area].”
- A collapsed “How this search worked” section below the cards. It starts with the black-on-white architecture sketch, then explains each call and its response in short text.

Keep the copy as spare as the mockup. Omit a reference-photo caption, result-count subtitle, and an introduction above the diagram. Mark saved results with a short status and retrieval date, as described below.

Reloading a completed search restores the results, reference thumbnail, ZIP, and whether the explanation was open. It does not upload again or start another search. This lasts for the browser tab's session; it is not a saved-search feature.

The app covers furniture on Craigslist across the US. It has one screen, with no accounts, saved searches, alerts, price or distance filters, pagination, or listing-detail pages. We will use SerpApi rather than scrape Craigslist or add an LLM.

The ZIP code selects one local Craigslist area. Show its name and hostname in the search explanation. “Near you” means that area; it does not promise a particular mileage or sort listings by distance. An unknown or unmappable ZIP gets a clear error before any paid search.

Visual mockup: [See the proposed screen](ui-mockup-looksalike-demo.html).

## Project choices

| Choice | What it means |
| --- | --- |
| Rails | One app serves the page, handles searches, and calls SerpApi. |
| React and Material UI | React handles the interactive screen. Material UI supplies inputs, buttons, loading indicators, and cards, with one shared theme and consistent keyboard focus styles. |
| Railway | One service hosts the public demo over HTTPS. |
| SQLite | A small database stores recent search results and usage counts. It does not store uploaded photos. |
| Public GitHub repository | Anyone can read the source and setup instructions. |

The directory contains the plan and an interactive React/Material UI mockup. The Rails app, Git setup, API calls, and deployment remain to be built. A SerpApi key is available to configure locally; it has not been read or used.

## Limits visitors will see

| Limit | Behavior |
| --- | --- |
| Location | Require a five-digit US ZIP code for live search. Preserve leading zeros and let visitors edit it before searching. |
| Photo size | Accept one JPEG, PNG, or WebP, up to 10 MB and 20 megapixels. Reduce it to at most 450,000 bytes before sending it. |
| Results | Show up to six distinct listings. Fewer results are acceptable. |
| Waiting time | Stop the server's work after 55 seconds. Give the browser 65 seconds to receive and show the outcome. |
| Simultaneous searches | Run one live search at a time. Another visitor gets a prompt “busy” message; the example and saved recent results remain available. |
| Public API allowance | Allow at most 10 search attempts per day and 180 in any rolling 30 days. |
| Per-visitor limit | Allow three searches per hour that need fresh results, tracked by browser session/IP address. |
| Repeated photos | Reuse a successful result for 24 hours, or an empty result for one hour. Show when it was retrieved. |
| Prepared example | Show a dated “Demo snapshot” that uses no API searches and works even when outside services are unavailable. |

A search attempt counts against the limit even if its outcome is uncertain. The app will not retry paid searches automatically. Development experiments and public searches share the account's allowance.

The server keeps uploaded photos only while handling the request. The browser retains a small reference thumbnail in this tab so results survive a reload; “Search again” clears it. Before upload, tell visitors that the reduced photo goes to SerpApi/Google for visual search. Search results may include expired listings, so the app must not claim that an item is still available.

## Steps

### 1. Set up the repository and a working Rails app

- [ ] Initialize Git with a `main` branch and a `deliver/looksalike-demo` working branch. Save the reviewed planning files as the starting point.
- [ ] Install a supported Ruby version, create the Rails app, and confirm it runs locally.
- [ ] Add React and Material UI to the Rails-served page, with a JavaScript build that runs locally and during deployment.
- [ ] Add setup instructions, an example configuration without secrets, and rules that keep private files out of Git.
- [ ] Add one command for the automated code, security, and test checks. Run the same checks in GitHub Actions.

### 2. Check whether the search idea works

Test five fixed photo/ZIP pairs: an ornate sofa in 10001, a modern sofa in 94103, a dining chair in 60601, a wood table in 02108, and a dresser in 98101. Use photos we own or have permission to reuse. Each photo is tested in its assigned area, keeping this comparison to five cases per approach.

Try Google Lens alone first, restricted to the Craigslist area selected by the ZIP code. If that fails, try Lens to produce a search phrase, followed by Google Images in that area. Each approach also needs a separate image-upload request.

**An approach passes when at least four of the five cases each return three relevant, distinct, accessible listings from the selected Craigslist area among the first six results, within 55 seconds.** Relevant means the same furniture category with a similar shape, material, or style. Check the listings by hand, but do not replace poor results to improve the score.

Spend at most **15 search attempts** on this comparison: up to five for Lens alone, then up to ten for the two-search approach. Stop testing an approach after two photos fail, because it can no longer pass. Keep up to **two additional attempts** for a final deployment check with a new photo, subject to the account and public limits.

- [ ] Build and test the photo compression and API request code without paid calls. Include the 55-second deadline and disable automatic retries.
- [ ] Build and verify the offline ZIP-to-area lookup, including leading-zero ZIPs and a clear outcome for ZIPs that cannot be located.
- [ ] Save the five prepared photo/ZIP pairs, selected areas, and exact search rules before testing, so the results can be judged consistently.
- [ ] Add a search-attempt counter that survives restarts and counts each request before it is sent.
- [ ] Run the comparison within its budget and save the results, timings, and reasons for each pass or failure.
- [ ] Use the passing one-search approach if possible; otherwise use the passing two-search approach.
- [ ] Package one successful result as the dated example, including its original ZIP/area, reference photo, and actual listing thumbnails with permission to reuse them.

**If neither approach passes, stop building features and bring back the evidence and the smallest proposed change.** Do not increase the budget, swap marketplaces, or use the example to claim that live uploads work. If we cannot obtain reusable listing images, flag that before promising a complete example.

### 3. Put the example online first

This checks the hosting setup before we expose paid searches to visitors.

- [ ] Create the public GitHub repository and publish the checked starting version.
- [ ] Deploy the example to Railway with live search switched off.
- [ ] Verify that the database is writable and that its records survive a restart and a new deployment.
- [ ] Use a temporary simulated search to check that Railway permits responses beyond 30 seconds and that the app stops work at its 55-second deadline.
- [ ] Remove or disable that temporary test route before allowing public live searches.

### 4. Build the complete visitor experience

Use the same compression and search rules that passed the experiment.

- [ ] Build the upload, example, and preview flow described above, with compression and clear file errors.
- [ ] Add ZIP entry, button enablement, and server validation. Select the search area with the tested lookup and include it in the explanation.
- [ ] Connect uploads to the chosen search approach and return up to six valid, distinct listing cards.
- [ ] Store recent results by photo and location, and show their age when reused.
- [ ] Enforce the spending limits and one-live-search rule, including during simultaneous requests and restarts.
- [ ] Build the results header and responsive cards described above using Material UI and the shared theme.
- [ ] Restore completed results after a reload in the same tab, without new API calls. Clear that saved view on “Search again.”
- [ ] Add understandable loading, empty-result, timeout, busy, and usage-limit messages. Keep the photo visible after an error and offer the example as another action.
- [ ] Add the architecture sketch and concise call-by-call explanation. Show the actual route, useful inputs and responses, and local processing. Count uploads separately from searches, and distinguish new calls from saved details.

### 5. Check the app before release

- [ ] Test the search rules, upload checks, errors, saved results, and spending controls using recorded responses instead of paid API calls.
- [ ] Verify location coverage across US states and DC, including rural areas, Alaska, Hawaii, leading-zero ZIPs, region boundaries, and unmappable ZIPs. Check that changing ZIP cannot reuse another area's results or relabel a saved example.
- [ ] Verify that simultaneous requests cannot exceed the limits and that the example and health check still respond during a live search.
- [ ] Verify that every image in the prepared example loads with external image and API requests blocked.
- [ ] Walk through uploads, the example, errors, and retries on desktop and mobile, including keyboard-only use.
- [ ] Check the disabled search button, inline example preview, and ZIP preservation. Verify that reload restores results without a provider call and that “Search again” clears them.
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

The public HTTPS link works without login. Visitors can try the complete example or upload a new photo with a US ZIP code. The location checks, five-case experiment, and final new-photo check have passed.

The page matches the mockup on desktop and mobile and works with a keyboard. A completed search survives a reload without repeating API calls. Errors explain what happened and offer a useful next action. Recent results and historical examples are labeled clearly.

Automated checks pass without paid searches. The database survives deployment changes. The public source, README, and recording explain how the app works and its limits.

## Technical appendix

These details preserve the implementation decisions. The steps above should be understandable without this appendix.

### Rails and Railway setup

Use Rails 8.1 with the latest compatible security patches. Pin exact Rails and Ruby versions during setup. The current shell uses macOS Ruby 2.6.10; install a project Ruby without changing the system Ruby. Node, Homebrew, Railway CLI, and GitHub CLI are available, but their authentication has not been checked.

Use ERB for the page shell and mount one React root for the search screen. Material UI and its default Emotion styling engine provide the controls and theme. Use Rails `jsbundling-rails` with esbuild to compile JSX and bundle pinned npm dependencies during asset preparation. Keep React/Material UI versions compatible and commit the lockfile. There is no separate frontend service, client-side router, or React server rendering. [Material UI setup](https://mui.com/material-ui/getting-started/installation/), [Rails JavaScript bundling](https://github.com/rails/jsbundling-rails)

React owns browser interactions and sends requests to same-origin Rails endpoints with Rails CSRF protection. Rails owns validation, credentials, search rules, cache, and quotas. Use Minitest, RuboCop, Brakeman, the JavaScript build, and GitHub Actions for normal checks. Bundle UI dependencies locally so the example has no CDN or font-service dependency.

The mockup source is `tasks/mockup/main.jsx`; its build command is documented in `tasks/mockup/README.md`. The generated HTML remains self-contained for direct viewing. Use Material UI's outlined inputs and theme focus states; avoid global focus rules that draw extra rings around inputs or headings. Keyboard focus and validation errors must remain visible.

Run Puma directly behind Railway's HTTPS service, with one worker and at least three request threads. Omit Thruster from the generated start command because its default timeout conflicts with the planned request length. Mount all production SQLite files at `/app/storage`. Set writable ownership for the app user and prepare the database at startup, after the volume is mounted.

Use a cheap health endpoint. If the intended database volume is missing or unavailable, disable live calls instead of creating a temporary replacement database. Keep the shared component boundaries in [ARCHITECTURE.md](../docs/ARCHITECTURE.md).

### ZIP codes and local areas

Use versioned, reusable offline postal-code data, initially GeoNames US postal data, to resolve a ZIP to a place and representative coordinates. Record the source date, license, attribution, and coverage. Include separately published US territory data where needed; do not assume one country file covers every US ZIP. Keep ZIPs as five-character strings. A format check is separate from a successful lookup. Distinguish malformed input from a ZIP missing in the dataset. [GeoNames postal data](https://download.geonames.org/export/zip/)

Bundle these files with Rails on the server. The browser sends one ZIP and receives the selected area; it does not download the ZIP dataset or the Craigslist-area catalog. Record the imported files' sizes and source dates during setup.

Keep an app-maintained list of US Craigslist areas with display names, approved hostnames, and documented center coordinates. Verify hostnames against the official directory. Use explicit ZIP/area overrides where needed, then choose the nearest regional center to the postal-code coordinates; break equal-distance ties by hostname. This is an approximate area-selection rule, not an official Craigslist boundary map. Record the source of center coordinates separately. Cover all states and DC, audit territory coverage, and report unresolved places before release. No geocoding service is called during a visitor's search. [Craigslist areas](https://www.craigslist.org/about/sites)

Resolve the ZIP before uploading the photo or reserving search allowance. Pass only the resulting approved hostname to the search and listing filter; never construct a host directly from user text. Save the chosen ZIP, area, mapping version, and search origin with the response. Freeze this lookup and its test cases before the paid experiment.

### Search requests and result rules

The first candidate is Google Lens with `type=visual_matches`, `q=site:<selected Craigslist hostname>`, and `country=us`. Lens has no documented ZIP or city-origin parameter; the selected hostname supplies the area restriction. That restriction still needs to pass our experiment. Keep provider order and name the selected Craigslist area in the explanation. A descriptive phrase is optional; do not invent an independent recognition result from listing titles. [Lens API](https://serpapi.com/google-lens-api)

The second candidate uses Lens with `type=all`. Treat its suggestions as possible search terms, not guaranteed descriptions of furniture style.

For phrase extraction:

1. Use the first non-empty Lens related query that contains a furniture category from a small saved word list.
2. If none qualifies, use the first category term plus descriptive words repeated in at least two of the first eight visual-match titles.
3. Remove words from a fixed stopword list and limit the phrase to eight words.
4. If this produces no usable phrase, return a weak-recognition outcome.

Save the category list, stopword list, and tie-breaking rules before scoring. Google Images gets the extracted terms and selected site's exact restriction, with US/English settings and a supported city search origin for that area. Pre-resolve and save the area's canonical origin from SerpApi's Locations API during data preparation. Search origin is context, not a distance filter. Order results by keyword overlap, using provider order to break ties. Present the phrase as a tentative “Looks like…” interpretation. [Google Images API](https://serpapi.com/google-images-api), [supported locations](https://serpapi.com/locations-api)

Read listing destinations from `visual_matches[].link` or `images_results[].link`, never from image URLs. Accept only HTTP(S) links on the exact selected, approved Craigslist hostname that point to individual listings. Remove duplicates by canonical URL/listing ID. A different Craigslist region is not an acceptable substitute.

Drop results missing a title, thumbnail, or source link. Use only supplied city or neighborhood details for a listing's location. If absent, show the selected area's name with a “Craigslist area” label. Handle broken images visibly and omit similarity percentages.

### Experiment records

Before the first scored call, save the compressed image bytes and hashes, assigned ZIPs, mapping version, selected hosts/origins, compression settings, request parameters, phrase rules, URL filters, duplicate rules, and result ordering in an experiment manifest. Verify location lookup, compression limits, and request deadlines offline first.

Check the account's remaining allowance before starting. The manual experiment uses its own durable counter from the first request, separate from the public app's daily limit. Its step 2 budget applies cumulatively across restarts.

Record sanitized responses, timings, phrase quality, card counts, missing fields, inaccessible links, relevance judgments, and timestamps under `docs/experiments/`. When the early-stop rule applies, mark the remaining photos untested. Do not add custom rescue queries.

Changing the algorithm invalidates the affected scores. Extra tuning needs a revised budget agreed with the user. The sample demonstrates this small test only; it does not establish general accuracy.

### Uploads and privacy

Rails independently checks the bytes, format, dimensions, and size against the photo limits above before contacting SerpApi. Show an actionable error if browser compression cannot meet the limit.

SerpApi's Image API accepts these formats up to 500 KB. Its `image_id` expires after ten minutes, so a new uncached search uploads the reduced image again. ID expiry does not prove that the provider has deleted the image. [Image API](https://serpapi.com/image-api)

Clean temporary upload files on success and failure. Do not accept arbitrary image URLs or fetch user-supplied URLs from the server. Remove keys, upload bodies, provider upload IDs, and credential-bearing URLs from logs and recorded test data.

### Saved results and the prepared example

Use browser session storage to restore a completed view: normalized cards, entered ZIP, resolved area, retrieval date, live/cache/snapshot status, sanitized search details, a small reference thumbnail, and the explanation's open state. Keep the upload's original bytes and provider upload ID out of this storage. Restore the previous result as-is, including its date; refreshing must never resubmit the search. An unfinished search is not a completed result and must not restart automatically.

Validate restored data and handle unavailable or corrupt storage by returning to the usable upload screen. “Search again” clears the saved result and thumbnail while retaining the ZIP in the current form. This browser copy is separate from the server cache and must never authorize calls or bypass limits.

For the saved results in step 4, use a cache key built from the reduced image's SHA-256 hash, ZIP, selected hostname/search origin, mapping version, and search/query version. Keep the original retrieval time and search details. Label a reused response “Cached.”

Apply the expiry times in the limits table. Provider failures must not be stored as successful results.

Save the example as a sanitized response snapshot in the repository. Record the image sources and reuse permission alongside the bundled files. Do not substitute unrelated stock images. Show its label immediately, retain historical listing links, and mark availability unverified. Never use it as the response to an unrelated upload.

Choosing the example fills the existing upload screen; it never opens a different design or submits immediately. The snapshot retains its original ZIP and area. If the visitor entered a different ZIP, offer the choice inline: use the example's ZIP or run a live search for the entered ZIP through the normal limits. Never silently overwrite the entered ZIP or relabel the snapshot as local to it. Loading the saved example needs no artificial wait for API calls.

The current mockup uses the selected purple Victorian couch, fills a blank ZIP with 94103, and preserves a ZIP already entered. Its cards and search details are fixed illustrations, not matching search evidence. Public release needs permission to reuse that reference photo or a suitable replacement, plus a genuine recorded result with its original ZIP. Keep the chosen photo's source in the mockup README.

### Spending and simultaneous requests

Make the public limits configurable. They are ceilings, not a claim about the account's remaining balance. The referenced free plan allows 250 searches per month; recheck the shared account before enabling live traffic. [Pricing](https://serpapi.com/pricing)

Before calling SerpApi, reserve enough allowance for the chosen approach's maximum search cost in one database transaction. Keep those reservations across restarts. Do not release reserved allowance when an in-flight request's outcome is uncertain.

Enforce the one-live-search rule through a persisted lock, called a lease. Reject another uncached request before uploading or reserving its search allowance. The lease must last longer than the server deadline plus cleanup time. Recover expired leases without refunding uncertain spend.

Reused results spend no provider allowance. The health endpoint must remain responsive alongside those results and the example.

### Deadlines, progress, and errors

The server deadline covers validation, upload, and all search calls together. Measure elapsed time with a monotonic clock so clock adjustments cannot extend it. Each network operation receives only the remaining time. Set `Net::HTTP#max_retries = 0` if using that client.

A browser disconnect does not guarantee that the provider stopped work. Do not automatically switch search approaches after a failure.

Use the shared API client for step 3's simulated search. Run its timing checks in both the production container and Railway.

Show one animated loading state. Display completed stages and their durations only when they actually finish. Do not claim progress based on a timer.

Give weak recognition, missing metadata/images, and provider errors their own outcomes alongside the states listed in step 4.

### How the search explanation works

Start with a black-on-white architecture sketch showing the browser, Rails, local ZIP/area files, and SerpApi. Use sketch-style boxes and labeled arrows, with solid requests and dashed responses. Number only the provider calls. Follow it with an ordered walkthrough of the approach the app used. Both the diagram and details must follow the recorded route and counts, rather than always showing three calls or six results.

Visitors do not choose between search approaches. The mockup illustrates one flow: upload, Lens, Images, and listing selection. That is three SerpApi requests: one upload and two searches. Keep both candidates in the development experiment: test Lens alone first, then Lens followed by Google Images if needed.

Begin the walkthrough with the browser's photo-and-ZIP request to Rails, then show these steps:

1. **Choose the local area.** Show the entered ZIP, the selected area, and its approved Craigslist hostname. Explain that this is an offline lookup, with no external request.
2. **Upload the photo.** Show the reduced photo's format and size, the upload endpoint, and a safe summary of the response. Explain that the returned image reference becomes the input to Lens. Count this as one upload request, separately from searches; do not expose the provider's upload ID or image bytes.
3. **Search with Google Lens.** Show the search inputs and useful response excerpts. For Lens alone, show how its matches become listing candidates. For the two-search approach, show which returned suggestions or titles produce the next query. Phrase extraction happens locally and is not another API call.
4. **Search with Google Images, if used.** Show the extracted phrase, site restriction, and search origin, followed by response excerpts that become listing candidates. Omit this call for the Lens-only approach.
5. **Choose the displayed listings.** Show counts before and after URL checks, duplicate removal, and missing-field checks, then the number displayed. These are local operations, with no external request.

For each external call, show its outcome and measured duration when available. Keep request details sanitized and response excerpts short. Mark failed or skipped stages honestly. Show the retrieval time separately from listing dates; search-attempt counts are not verified bills.

The local mockup uses completed-search wording to preview the finished design. Its README records that the requests, responses, and counts are modeled; they are not evidence of working API calls. In the live app, cached results and the prepared snapshot show zero new calls, with the original calls, counts, timings, and retrieval date shown separately when recorded. Never present saved or modeled details as a live search that just ran.

### Verification and documentation

The offline checks in step 5 cover extraction, listing URLs, duplicates, missing metadata, errors, cache expiry, and usage accounting. Include browser and server upload limits, actual request counts after network failure, lease recovery, and simultaneous different uploads.

Add one request-level integration flow. The browser walkthrough also checks focus, error announcements, broken images, double submission, and timeout recovery. Check reload after an upload and after the example, including a leading-zero ZIP, open and closed explanations, unavailable storage, and an interrupted search. Restoring a completed view must make zero upload or search calls.

Check the explanation for both search approaches, failures, cached results, and the example. Each call must show how its response feeds the next step; local work must not increase the upload or search counts.

Add instructions to refresh recorded responses, experiment results, and the recording to the README contents listed in step 6.

The completed [Pro analysis](tmp/pro-analysis-looksalike-demo.md) records the earlier technical review and seven adopted findings. It predates the later US ZIP, Material UI, reload, and diagram changes; it does not validate those additions. They still need the implementation checks above. Implementation begins after the plan is accepted.

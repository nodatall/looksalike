# Frozen feasibility inputs

Status: **stopped after neither route passed**. The live comparison used six search attempts and four separate upload attempts, with zero displayable cards. Both routes stopped at two failed cases; the remaining three cases on each route are untested. Read the [results and proposed diagnostic](results.md) and [recorded live evidence](live-evidence.json). No further calls or feature/deployment work are authorized by this result.

[manifest.json](manifest.json) records the exact image bytes, source URLs and license checks, browser/compressor metadata, ZIP mappings, request templates, and 26 artifact hashes. Its checksum is in [manifest.sha256](manifest.sha256). The manifest and rules preserve their historical pre-run status and are not live result logs. [rules.md](rules.md) freezes query extraction, destination/thumbnail validation, deduplication, and route ordering. The five cases must remain in this order:

| Reference | ZIP | Selected host | Prepared bytes | Dimensions |
| --- | --- | --- | ---: | --- |
| Ornate sofa | 10001 | newyork.craigslist.org | 287,591 | 1067 × 1600 |
| Modern sofa | 94103 | sfbay.craigslist.org | 137,444 | 1600 × 1067 |
| Dining chair | 60601 | chicago.craigslist.org | 353,078 | 1067 × 1600 |
| Wood table | 02108 | boston.craigslist.org | 241,167 | 1600 × 1067 |
| Dresser | 98101 | seattle.craigslist.org | 112,541 | 1600 × 1067 |

The total prepared image size is 1,131,821 bytes. Every image came from the actual browser `jpeg-v1` preprocessor at quality 0.86, using Chrome 153.0.0.0. Each passed the server validator. The modern sofa and table use the same licensed photographs downloaded at 2400 × 1600; their original downloads exceeded the 20-megapixel source limit. No alternative encoder or dimension-limit bypass was used.

The source photographs are by Sueda Dilli (Pexels), Phillip Goldsberry, Kelly Miller, Leighton Robinson, and Oak+Motion (Unsplash). The session checked regular free licenses on September 17, 2026 using [Pexels's license](https://www.pexels.com/license/) and [Unsplash's license](https://unsplash.com/license), plus four individual photo pages. Kelly Miller's individual page could not be accessed; the free dining-chair search entry identified the creator and exact download instead. The manifest preserves that narrower evidence, every source page, and exact download URL. This evidence applies to these reference photos; it supplies no reuse permission for future listing thumbnails.

From the repository root, verify the frozen bytes, rule/data hashes, server image acceptance, and current ZIP resolution before dispatch:

```sh
script/verify_experiment.rb
```

Normal tests remain offline. This preflight does not dispatch requests, modify the manifest, count paid attempts, or judge relevance. The manual runner reserves durable attempts before dispatch and requires a fresh recorded account allowance.

Evaluate Lens-only first, then the two-search route only if needed. A route passes with at least four of these five cases yielding at least three relevant, distinct, accessible listings from the correct selected area among the first six, within 55 seconds. Stop a route after two failed cases. The cumulative comparison cap is 15 attempted searches; a separate final smoke cap reserves two more. There are no automatic retries. Record actual judgments, failures, timing, requests, and spending in later evidence without overwriting this frozen manifest. After the first live attempt, any policy/input change requires a new experiment version before more scored calls. Pre-run integration corrections are explicitly recorded in the manifest; the reference bytes and recognition/filter/ranking policy remain unchanged.

## Manual operator commands

The commands below document the completed comparison workflow. Both routes are now stopped; do not initialize a replacement ledger or rerun cases. Further diagnostic execution requires agreement on a revised plan and budget allocation. Automated tests and the default command remain offline. Run from the repository root with Ruby 3.4.10 on `PATH`. Configure the key privately in `.env.local`; never pass it as a command argument. The tool accepts only the local development environment with no `DATABASE_URL`, including dotenv files. It positively verifies the fixed writable ledger path `storage/feasibility-v1.sqlite3`; it does not create missing parent directories or offer reset/delete commands. Keep that file across restarts. Explicit offline `init` is required once; account/run commands never create a missing ledger. Initialization refuses an existing ledger or live evidence, and offers no force option. Restore the original ledger if it is lost after any attempt.

```sh
script/experiment                         # Offline hashes/photos/locations; no ledger creation
script/experiment run lens_only           # Still only offline preflight without --execute
script/experiment init                    # One-time offline creation; refuses existing ledger/evidence
script/experiment account --execute       # Explicit free account request; safe summary only
script/experiment run lens_only --execute # Exactly the next fixed case, then stop for judgment
script/experiment report                  # Inspect results, attempted stages, unfinished cases
```

The explicit account request uses SerpApi's [free Account API](https://serpapi.com/account-api). Only an active account with integer `total_searches_left` is accepted. The ledger saves check time, total allowance, and the existing search-attempt count; allowance decreases conservatively by every later attempt, including uncertain failures. A check expires after one hour. Missing, stale, inactive, or insufficient allowance blocks upload. The runner requires enough allowance for the next route's maximum calls (one or two); it cannot guarantee credits against unrelated account activity. Recheck explicitly when necessary. Neither account checks nor uploads increment the search budget.

Each execution verifies all frozen hashes and all five photos/mappings before claiming a case. The same 55-second deadline covers that validation, upload, calls and normalization. Lens-only has a cap of five attempts, Lens-then-Images ten, and the shared comparison cap is 15. The reserved final two-call smoke budget is unavailable to this tool. All reservations commit before dispatch; failure, timeout, interruption or an uncertain response never refunds an attempt. There are no retries or automatic reruns.

After a run, inspect `live-evidence.json` and open the original returned listing links manually. Create a private judgment JSON file outside the evidence folder. Include every original card in its original order, each with these five boolean observations and a concrete reason:

```json
{
  "reason": "Explain the overall manual assessment.",
  "cards": [
    {
      "position": 1,
      "category_match": true,
      "style_match": true,
      "distinct": true,
      "correct_area": true,
      "accessible": true,
      "reason": "State the observed category, shape/material/style, area and accessibility."
    }
  ]
}
```

Repeat that card object for every original candidate; the one-card illustration above cannot pass. `style_match` means similar shape, material, or style. Do not substitute listings, change their order, put credentials in reasons, or count duplicate listings as distinct. Missing/incorrect card positions or missing reasons/booleans are rejected. A card passes only when all five observations are true. A case passes only with at least three passing cards, technical success, and total elapsed time at most 55 seconds.

```sh
script/experiment score lens_only ornate-sofa /absolute/path/to/judgment.json
script/experiment run lens_only --execute
```

The next case stays blocked until the current judgment is complete. Two judged failures stop that route and leave remaining cases untested. Only then may the operator run `script/experiment run lens_then_images --execute`, starting with the ornate sofa again under that distinct route. Five judged Lens-only cases with at least four passes end the comparison; the two-search route remains blocked.

After interruption, `script/experiment report` exposes the claimed case and its immutable stage reservations even when no outcome was saved. A reservation proves an attempted stage, not a completed response. Do not rerun it. Score the unfinished case with `cards: []` and a specific interruption reason; it is recorded as failed and normal order/early-stop rules apply. If evidence-file writing was interrupted after the database commit, `script/experiment export` recreates the sanitized report from the ledger without provider traffic. The export preserves stored dates and judgments. The SQLite ledger is authoritative; do not delete it or replace it to obtain a fresh budget.

`live-evidence.json` is created only by explicit execution/scoring/export against an existing experiment. It contains manifest identity, reserved stages/dates, actual call durations when known, allowlisted bounded excerpts, original normalized candidates/filter counts, and manual judgments. It excludes image bytes, upload references, keys, raw provider/account responses and metadata URLs. Technical results and human judgments remain separate. Normal tests exercise this format only in disposable directories and do not create live evidence here.

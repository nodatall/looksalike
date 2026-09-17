# Frozen feasibility inputs

Status: **not run**. These are licensed reference photos and offline preparation evidence, not search results or proof of feasibility. No upload or search has been dispatched.

[manifest.json](manifest.json) records the exact image bytes, source URLs and license checks, browser/compressor metadata, ZIP mappings, request templates, and 20 artifact hashes. Its checksum is in [manifest.sha256](manifest.sha256). [rules.md](rules.md) freezes query extraction, destination/thumbnail validation, deduplication, and route ordering. The five cases must remain in this order:

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

Normal tests remain offline. This preflight does not dispatch requests, modify the manifest, count paid attempts, or judge relevance. A later manual runner must reserve durable attempts before dispatch and verify the account's remaining credits.

Evaluate Lens-only first, then the two-search route only if needed. A route passes with at least four of these five cases yielding at least three relevant, distinct, accessible listings from the correct selected area among the first six, within 55 seconds. Stop a route after two failed cases. The cumulative comparison cap is 15 attempted searches; a separate final smoke cap reserves two more. There are no automatic retries. Record actual judgments, failures, timing, requests, and spending in later evidence without overwriting this frozen manifest. Any policy/input change requires a new experiment version before more scored calls.

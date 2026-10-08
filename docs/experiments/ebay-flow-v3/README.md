# Venice photo fallback: live comparison

The flow passed the agreed four-of-five requirement on September 28, 2026. All five searches finished in 5.4–18.2 seconds. Venice was needed for three photos and returned valid descriptions each time. This is a small fixed-photo comparison, not a general accuracy estimate or a deployed-app test.

| Photo | Query source | Search phrase | Relevant and accessible, out of six | Total time | Result |
| --- | --- | --- | ---: | ---: | --- |
| Ornate sofa | Lens | vintage sofa | 2 | 7.91 s | Fail |
| Modern sofa | Venice | teal velvet tapered legs sofa | 6 | 11.07 s | Pass |
| Dining chair | Venice | light wood finish turned legs chair | 4 | 17.68 s | Pass |
| Coffee table | Lens | farmhouse coffee table | 5 | 5.41 s | Pass |
| Dresser | Venice | glossy white finish horizontal drawer fronts dresser | 4 | 18.19 s | Pass |

The criterion is unchanged: at least three distinct, accessible US-located items among the first six must share the furniture category and a similar shape, material, or style. Four photos must pass within 55 seconds. All 30 listing pages opened during manual review. Listings were not replaced or reordered to improve scores.

## What improved and what remains weak

Venice successfully described the modern sofa, chair and dresser from their photos. Its calls took 3.91, 3.75 and 4.63 seconds. Each returned HTTP 200, the selected model, a completed structured answer and token usage. No visitor description was needed.

Some passing items are weak material-only or style-only matches. The modern sofa has two close teal matches; its burgundy, cream and brown sofas qualify under the existing material rule despite their different appearance. The chair result contains four wood-frame chairs but also two sets of replacement legs. These weaknesses remain visible in the saved cards and individual judgments.

The ornate sofa failed because four promoted items occupied the first four slots: a modern sectional, a console table and two rugs. The following two sofas were relevant. Lens returned “vintage sofa,” so the current fallback trigger did not call Venice. The trigger treats any recognized trait as sufficient; it does not measure phrase quality. This remains a limitation, not a failed Venice request.

The coffee table passed without Venice. The dresser passed with three fairly similar wide white dressers and one weaker modern-style black chest. Its other two results failed.

## Calls and allowance

This batch used **10 SerpApi searches, five uploads and three Venice calls**, with no retries. Recorded development usage is now **39 SerpApi search attempts**. The free account check showed 224 searches before the batch and [214 after it](account-after.json). The separate two-search deployment reserve remains unused.

The vision ledger reserved $0.03 before each call, $0.09 total. The reported usage totals 5,463 input tokens and 100 output tokens. At the public model catalog rates frozen in the manifest ($0.21 and $1.90 per million tokens), that is about **$0.00134**. This is a token-based estimate, not a verified invoice.

## Evidence and verification

The [manifest](manifest.json) and [checksum](manifest.sha256) freeze the five original photo hashes, source code, prior evidence, 16 historical ledger tables, request parameters and public model catalog snapshot. Each request was reserved in a separate durable experiment ledger before dispatch. The original reports and scores remain unchanged.

| Photo | Response | Judgment |
| --- | --- | --- |
| Ornate sofa | [Response](ornate-sofa.json) | [Judgment](ornate-sofa-judgment.json) |
| Modern sofa | [Response](modern-sofa.json) | [Judgment](modern-sofa-judgment.json) |
| Dining chair | [Response](dining-chair.json) | [Judgment](dining-chair-judgment.json) |
| Coffee table | [Response](wood-table.json) | [Judgment](wood-table-judgment.json) |
| Dresser | [Response](dresser.json) | [Judgment](dresser-judgment.json) |

The disposable operator passed 11 offline checks with 110 assertions before freezing. They cover both query paths, reservation before dispatch, spending caps, deadlines, filtering, failures without retries and stopping after two failed photos. `test_disposition: probe_only`: these checks support the manual experiment rather than a permanent public execution tool.

Post-run read-only verification matched all five outcomes and judgments to the ledger, checked first-six ordering, US filtering, query construction, scoring and timing, and confirmed all 77 frozen file hashes and 16 historical table hashes. It found no incomplete reservations, configured keys or private photo payloads in the saved evidence.

The full `bin/check` passed: 83 Ruby tests, 1,048 assertions, eight JavaScript tests, style checks, security/dependency audits, build and Rails loading. Normal checks made no paid calls. A probe-only HTTP transport recorded safe Venice diagnostic fields; the actual application client, query preparation, prompt, schema and parsing were used. Production HTTP behavior is covered separately by offline tests. The ignored runner and ledger are local operator artifacts, not a portable replay harness.

## Next step

The search-quality requirement is met. The remaining work is the saved example, visitor flow, quotas, caching, explanation, public repository and Railway verification. The visitor screen still has no live search wiring.

The modern-sofa response is the candidate for the dated example. Its reference photo has documented Unsplash reuse provenance. The listing-thumbnail URLs do not establish permission to bundle those images in the public repository. The plan requires documented reuse permission and an example that works with external images blocked; that part of packaging remains unresolved. No seller photos have been downloaded or published as app assets. See the [prepared example manifest](../../examples/modern-sofa-2026-09-28.json).

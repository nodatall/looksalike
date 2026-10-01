# Repaired photo-to-eBay comparison

The September 29, 2026 comparison **passed four of five cases**. The chair and table repairs worked. The ornate sofa failed because Venice exceeded its 15-second limit; no eBay search ran for that photo.

Each case needed three relevant, distinct, accessible US-located listings among its original first six within 55 seconds. Relevance means the same furniture category with similar shape, material or style. Every returned first-six item was reviewed in provider order without replacements.

| Photo | Relevant and accessible | Total time | Outcome |
| --- | --- | --- | --- |
| Ornate sofa | No listings | 18.6 seconds | Failed: vision timeout |
| Modern sofa | 4 of 6 | 5.0 seconds | Passed |
| Dining chair | 5 of 6 | 33.8 seconds | Passed |
| Coffee table | 6 of 6 | 16.5 seconds | Passed |
| Dresser | 3 of 6 | 17.0 seconds | Passed |

The chair results contain complete chairs rather than loose spindles. Venice identified the table as “white wood barn door hardware coffee table.” These results support the repairs, but do not establish their general accuracy.

Many matches are partial. Chair upholstery and back designs differ from the reference. Two Windsor listings sell different quantities of the same design. The dresser list includes two finish variants of one design and three unrelated storage-bin units. Distinct listing IDs do not guarantee design variety. Title filtering is eligibility checking, not visual ranking.

## Calls and evidence

The batch recorded nine SerpApi search attempts, five uploads and four Venice calls, with $0.12 reserved for Venice. Reservations are conservative limits, not billing receipts. There were no retries. The separate two-search deployment reserve remains untouched. The final free account check reported 197 searches remaining; recorded development attempts total 57 SerpApi searches and 11 Venice calls.

The model remained `qwen3-vl-235b-a22b`, using prompt v2 and the v2 title filter. Requests omitted eBay country, ZIP and pickup filters. Accepted rows required an explicit “Located in United States” response field. The shared deadline remained 55 seconds, with at most 15 seconds for Venice.

[manifest.json](manifest.json) freezes the five photos, request rules, budget, policy versions and source copies. [verification.json](verification.json) confirms the file hashes, all 25 prior ledger tables, matching outcomes and judgments, no incomplete reservations, and no configured key values in the records. The operator checks passed 17 offline tests and 145 assertions before dispatch. The app checks passed 90 Ruby tests with 1,255 assertions and eight JavaScript tests.

Each photo has a response file and a separate judgment file in this directory. Earlier comparisons, including the failed [v5 batch](../ebay-flow-v5/README.md), retain their original scores. Listing access was checked at review time and can change. This comparison does not verify the visitor UI or deployment.

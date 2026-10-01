# Short furniture queries

Use one common furniture name and at most two useful visual traits. Remove duplicate words, marketing text, and incomplete terms such as “seater.” Choose the phrase before searching; do not automatically broaden it and send another request.

The rule uses a small saved vocabulary. It keeps the first recognized trait from each group (color, material, style), selects at most two groups in source order, and puts the category last. Query aliases include “couch” and “settee” → “sofa,” “grey” → “gray,” and “wooden” → “wood.” The tokenizer used to rank listing titles is unchanged.

The user approved this rule after showing that Craigslist found no results for `sofa green velvet seater`, but returned relevant sofas when “seater” was replaced with “sofa.” This supports testing shorter wording. It does not establish what Google Images will return.

## Focused comparison

One Google Images request ran for each phrase, keeping the original site restrictions, origins, and listing checks:

| Case | Earlier phrase | New phrase | Area |
| --- | --- | --- | --- |
| Modern sofa | `sofa green velvet seater` | `green velvet sofa` | San Francisco / `sfbay.craigslist.org` |
| Ornate sofa | `sofa antique photos download free settees vintage` | `antique sofa` | New York / `newyork.craigslist.org` |

The new rule processes phrases saved in the original comparison. The modern case also has saved Lens title excerpts for an offline replay. The ornate case has only the earlier extracted phrase, so this test cannot replay its full Lens response.

This allocation permits exactly two Images attempts, bringing combined usage from eight to at most ten of fifteen. It includes no upload, Lens call, automatic retry, alternate query, or site-filter change. The separate final two-attempt smoke allowance remains untouched. Neither case can establish that the complete five-photo flow passes.

## Preserving the original experiment

The original manifest, rules, evidence, and ledger rows stay unchanged. The previous query source is preserved in [search_query_v1.rb](search_query_v1.rb), with its original hash. The new manifest freezes the revised query source and the two requests before execution.

The v1 runner intentionally refuses the changed policy. Its historical verification belongs to Git revision `79e05a3`; do not rewrite its hashes to make the new policy pass as v1. Query-v2 checks the new policy and verifies that the other 25 original artifacts remain unchanged.

The probe retains bounded response classifications, filter counts, and sanitized host/path summaries. SerpApi documents that `Success` can include empty results; the probe also checks the reported image-result state when present. [Response status documentation](https://serpapi.com/api-status-and-error-codes)

## Outcome

Both requests completed on September 18, 2026. The [recorded responses](results.json) show HTTP 200, `Success`, the expected query echoed back, and “Results for exact spelling.”

| Case | Returned images | Filter results | Distinct candidates | Time |
| --- | ---: | --- | ---: | ---: |
| Modern sofa / San Francisco | 100 | All 100 on the wrong hostname | 0 | 3.05 seconds |
| Ornate sofa / New York | 100 | 91 search/category links rejected; 9 listing links included 7 duplicates | 2 | 22.68 seconds |

The shorter New York phrase produced listing candidates where the previous request returned no images. Both candidates opened in the browser and showed New York locations, but neither matched the ornate sofa. One was a mixed antiques listing with plain black leather sofas; the other was a white sculptural lounge chair whose description included many furniture keywords. See the [manual checks](manual-checks.json).

The San Francisco phrase still produced no links on `sfbay.craigslist.org`. The first 50 distinct recorded hosts cover 87 results and include retail, social, and editorial sites. The remaining 13 results are grouped as `other_hosts`, so this record does not establish whether any used another Craigslist hostname. All 100 failed the unchanged selected-host check.

Shorter wording is now implemented, but it did not produce a passing result in these cases. Search-page links and irrelevant listings remain obstacles. The successful browser visits also confirmed that the two old regional listing URLs redirect to `www.craigslist.org/view/d/...`; that alone does not establish how to verify the region of a new URL from search results. The next investigation should address which search results and URLs can provide individual local listings, without weakening the region check.

Exactly two new search attempts ran, bringing the total to **10 of 15**. Five comparison attempts remain unused; the two final smoke attempts remain untouched. No further calls ran. The original scores still stand, and feature work and deployment remain paused.

Validation passed: **64 Ruby tests / 585 assertions, 8 JavaScript tests**, lint, dependency audits, security analysis, build, and Rails loading. The temporary replay probe passed 29 offline assertions. Root reviewed the probe before execution, verified the saved results against its two ledger rows, and confirmed the original five ledger tables and historical evidence are unchanged. The old query source matches its frozen hash; the other 25 original artifacts are unchanged. The new manifest and source hashes passed preflight before each request.

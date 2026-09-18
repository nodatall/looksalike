# Two-search diagnostic — September 17, 2026

**The modern-sofa search returned 100 links, all outside Craigslist.** The filter correctly rejected them. The ornate-sofa search returned no images and an error field. These results do not establish a working search approach.

The [sanitized evidence](results.json) records two approved Google Images requests at 04:44 UTC on September 18 (September 17 in California). Both used the exact queries and locations from the [original comparison](../feasibility-v1/results.md). There were no uploads, Lens calls, query changes, or retries.

| Case | Response | Links | Filter outcome | Request and processing time |
| --- | --- | ---: | --- | ---: |
| Ornate sofa / New York | HTTP 200, `Success`, error field present | 0 | No links to inspect | 7.82 seconds |
| Modern sofa / San Francisco | HTTP 200, `Success`, no error field | 100 | All 100 rejected for the wrong hostname | 3.67 seconds |

## What this tells us

The modern query included `site:sfbay.craigslist.org`, but its results came from 44 other hosts. Examples include Amazon, Wayfair, Homary, Article, and Home Depot. None came from any Craigslist hostname. For this request, the failure happens before the individual-listing URL check: accepting newer Craigslist URL shapes would not recover a card. The response does not explain why the site restriction was ineffective.

The ornate response had no image results. Its error text did not match the probe's single allowlisted empty-results message, `Google hasn't returned any results for this query.` It remains classified as `provider_error`; it could be a different empty-results message or another error. Arbitrary error text was deliberately not retained. HTTP 200 and `Success` do not prove that usable results were returned. [SerpApi status and error contract](https://serpapi.com/api-status-and-error-codes)

These are new observations, not a reconstruction of the earlier responses. They leave both original route scores unchanged. The earlier Lens failures were not retested.

## Recommended next step

Revise the search step before building more features. Keep the exact Craigslist-area filter. First inspect the documented query behavior and improve offline handling of successful responses with no results. Any further live experiment needs a specific revised query or retrieval method and an agreed allocation from the seven unused comparison attempts. This diagnostic does not show that a query change will solve the problem.

## Checks and budget

The temporary probe passed syntax validation and 30 offline assertions before execution. Checks covered response classification, URL rejection reasons, credential redaction, duplicate prevention, the two-attempt cap, durable reservations, and failed requests retaining their reservation. Each live attempt was recorded before dispatch, with a 55-second deadline, a 2 MB response limit, and automatic retries disabled.

The separate diagnostic ledger records **2 attempts**, bringing combined usage to **8 of 15 comparison attempts**. These are attempt counts, not verified charges. The two final deployment-check attempts remain untouched. No further diagnostic calls are authorized by this allocation.

The original evidence, manifest, all 26 frozen artifacts, and all rows in the original four ledger tables are unchanged. The saved results match the two diagnostic ledger rows. Application code is unchanged; the full application suite was not rerun for this probe. Feature work and deployment remain paused because neither search approach passed.

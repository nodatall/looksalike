# Feasibility v1 results — September 17, 2026

**Neither route passed.** Both stopped after their second failed case, as required by the frozen rules. The four executed cases produced zero displayable cards and zero passing cards. Feature work, a final snapshot, publishing and deployment remain stopped at this gate.

The [recorded evidence](live-evidence.json) contains **6 search attempts and 4 separate upload attempts**: two searches for Lens-only and four for Lens-then-Images. These are durable attempt counts, not verified bills. Nine of the 15 comparison attempts remain unused; the separate two-attempt final smoke allowance is untouched. No failed request was retried and no query or result was substituted.

| Route / case | ZIP | Upload (ms) | Lens (ms) | Images (ms) | Total (ms) | Outcome |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Lens-only / ornate sofa | 10001 | 666.485 | 9,183.067 | — | 10,091.432 | Failed: all 60 returned links rejected; 0 cards. |
| Lens-only / modern sofa | 94103 | 485.213 | 6,186.699 | — | 6,889.160 | Failed: Lens stage failed; 0 cards. |
| Lens + Images / ornate sofa | 10001 | 712.188 | 6,777.983 | 1,945.608 | 9,650.052 | Failed: Images stage failed; 0 cards. |
| Lens + Images / modern sofa | 94103 | 643.599 | 9,891.911 | 3,839.771 | 14,605.992 | Failed: all 100 Images links rejected; 0 cards. |

All uploads succeeded. Total duration includes validation and orchestration as well as provider stages; all four cases finished within 55 seconds. The ornate Lens-only and modern two-search cases completed technically, but failed the minimum of three usable listings. The other two cases have only a generic failed-stage classification. The dining chair (60601), wood table (02108), and dresser (98101) remain **untested on each route**, not scored as failures. Neither route can reach four passing cases out of five after two failures.

The evidence does not establish that Craigslist generally cannot work. Rejected destination links were not retained, so we cannot distinguish wrong-area/category pages from current individual-listing URL shapes rejected by the strict filter. The ornate two-search query picked up `photos`, `download`, and `free`; the modern query extracted `sofa green velvet seater`, yet all 100 links were rejected. Neither a query change nor a URL-filter change is proven to fix this.

The failure records also cannot distinguish empty search results from HTTP, service, or parsing errors. SerpApi documents that a successful search with no results can include a top-level `error` field. The current [client](../../../app/services/serp_api/client.rb) classifies every such field as unavailable. A zero-network, injected-transport probe confirmed that HTTP 200 plus `Success` and a documented empty-results `error` becomes `Client::Error` with code `unavailable`. That verified behavior limits diagnosis; it does **not** establish what caused either observed failure. See [SerpApi's status/error contract](https://serpapi.com/api-status-and-error-codes).

## Proposed next step — not authorized or executed

Seek agreement on a revised plan and allocation for one separate diagnostic: **at most two additional Images requests**, using two of the nine unused comparison attempts. This would cap combined usage at **8/15** and leave the final two smoke attempts untouched. Freeze these exact recorded queries and origins, with `engine=google_images`, `gl=us`, and `hl=en`:

| Case | Exact query | Exact location |
| --- | --- | --- |
| Ornate sofa / NYC | `sofa antique photos download free settees vintage site:newyork.craigslist.org` | `New York,New York,United States` |
| Modern sofa / SF | `sofa green velvet seater site:sfbay.craigslist.org` | `San Francisco,California,United States` |

Make no new upload or Lens call, query edit, or automatic retry. Reserve each attempt before dispatch even if a provider cache hit might avoid a bill. Record safe HTTP/status/error classifications, rejection counts, and at most ten sanitized host/path examples, capped at 200 characters each with credentials, query strings and opaque identifiers omitted. Keep exact-area checks and original scoring unchanged. Its purpose is to identify current URL rejection reasons and distinguish empty results from other stage failures; it would not replace these v1 scores or prove that the product is feasible.

The historical [manifest](manifest.json), its checksum, the [rules](rules.md), reference bytes, and existing live evidence remain unchanged. Their `not_run` wording records the pre-run freeze; this report and the separate live evidence describe the completed comparison.

# Nationwide eBay retry

The same nationwide `green velvet sofa` request failed again. SerpApi returned **HTTP 503 after 90.34 seconds**, with the message: “We couldn't get valid results for this search. Please try again later.”

This was one user-approved retry on September 18, 2026, Pacific time (September 19 at 05:57 UTC). The query and filters were unchanged: `engine=ebay`, `_nkw=green velvet sofa`, `ebay_domain=ebay.com`, `_salic=1`, and `_ipg=25`. There was no ZIP or pickup-only restriction. We extended only this diagnostic's deadline to 110 seconds to capture the provider's final response. The application's 55-second target is unchanged.

The provider echoed all five parameters and recorded 90.11 seconds of processing. Its search ID is `6aae246128b27b1e1d014e8a`. No listings were returned because the request failed; this is not evidence of no matching inventory.

The [previous request's archived response](../ebay-us-v1/archive-diagnosis.json) also shows HTTP 503 after 90.11 seconds. Two identical failures make this particular nationwide request unsuitable for the demo as tested. They do not identify the underlying cause or prove that all eBay queries fail. The earlier antique-sofa request used different parameters and succeeded.

## Evidence

- [Frozen request and limits](manifest.json), with [checksum](manifest.sha256).
- [Account allowance before dispatch](account.json).
- [Complete sanitized outcome](results.json).

One attempt was reserved durably before dispatch. Combined usage is **14 of 15 attempts**; one remains. The separate two-attempt deployment allowance is untouched. No automatic retries, uploads, Lens searches, pagination, or listing-page requests ran. Prior ledger rows and frozen source hashes were preserved. A local path error was corrected before any network request or reservation.

This retry changed no application code. Verification checked the manifest, unchanged prior ledger rows, one reservation, saved outcome, and absence of the API key in the saved artifacts. The next useful test would isolate a parameter or use SerpApi's internal diagnostics; repeating this identical request again would not isolate the cause.

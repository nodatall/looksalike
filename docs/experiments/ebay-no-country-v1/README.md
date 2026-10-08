# eBay test without the country filter

Removing `_salic=1` returned **60 listings in 2.12 seconds**, with HTTP 200 and provider status `Success`. The same query had failed twice with the country filter, each time after about 90 seconds.

The user approved one test with only that filter removed. It ran on September 18, 2026, Pacific time (September 19 at 06:05 UTC). The remaining parameters were unchanged:

```json
{
  "engine": "ebay",
  "_nkw": "green velvet sofa",
  "ebay_domain": "ebay.com",
  "_ipg": "25"
}
```

SerpApi echoed those parameters without `_salic`. It reported 1.73 seconds of provider processing and search ID `6aae260d9f8abc2f7426f723`. The 110-second diagnostic deadline was unchanged from the preceding retry; this result also arrived within the application's 55-second target.

## What this tells us

The country filter is the likely cause of the failed requests, though these sequential tests cannot prove the provider's internal cause. SerpApi supplied `Located in United States` for 59 listings and `Located in Philippines` for one. Filtering those returned location fields locally retained 59 distinct item links with thumbnails and prices.

The first six included a green velvet sofa at $399.90 and an olive green sofa at $3,999. Four of those first six were sponsored. Listing photos, page accessibility, and similarity to the reference were not manually assessed in this test, so counts do not establish match quality or a full photo-to-listings pass.

The practical next change is to omit the provider country filter and keep only listings explicitly marked US-located in the response. This test did not change the application or mockup.

## Evidence and limits

- [Frozen request and limits](manifest.json), with [checksum](manifest.sha256).
- [Account allowance before dispatch](account.json).
- [Sanitized results, listing fields, and timings](results.json).

One attempt was reserved before dispatch. Combined experiment usage is **15 of 15 attempts**; the separate two-attempt deployment allowance is untouched. No retries, uploads, Lens searches, pagination, or listing-page requests ran. Verification checked the manifest, unchanged prior ledger rows and source files, the single reservation, the saved outcome, and absence of the API key in the artifacts. No application code changed.

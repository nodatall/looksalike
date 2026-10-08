# Nationwide eBay test

The nationwide green-sofa request timed out after **55.01 seconds**. No completed response was captured, so this test cannot establish result quality, US filtering, or whether matching items were available.

The user approved a photo-only demo that searches eBay across the United States, without a ZIP or pickup-only restriction. This was one test of the saved phrase `green velvet sofa`, not a fresh photo upload or Lens search.

## Request

The request ran on September 18, 2026, Pacific time (September 19 at 05:15 UTC):

```json
{
  "engine": "ebay",
  "_nkw": "green velvet sofa",
  "ebay_domain": "ebay.com",
  "_salic": "1",
  "_ipg": "25"
}
```

`_salic=1` is the documented United States country setting. The request omitted the ZIP, pickup-only filter, and previously rejected `LH_PrefLoc=Domestic` value. [SerpApi country options](https://serpapi.com/ebay-location-options)

The local deadline stopped the request after 55,009 milliseconds. No HTTP status, result count, or listing cards were available to assess. This does not establish whether SerpApi later completed the search. The request was not retried, and no archive polling, uploads, Lens calls, or pagination ran.

## Records and limits

- [Frozen request and limits](manifest.json), with [checksum](manifest.sha256).
- [Observed outcome](results.json).
- The configured account was active with 239 searches remaining before dispatch. That account balance is separate from the local attempt counter.
- One attempt was durably reserved before dispatch and remains spent despite the timeout.

Combined experiment usage is **13 of 15 attempts**. Two remain unused. The separate two-attempt deployment check remains untouched. Earlier experiment files, scores, and ledger rows are unchanged.

The plan now specifies photo-only input and nationwide eBay results. The app and mockup migration, successful country-filter check, fresh Lens-to-eBay flow, and broader photo comparison remain pending. The earlier successful antique-sofa trial used ZIP and pickup settings, so it is not proof that this new request works.

Verification checked the frozen request, prior file and ledger hashes, single reservation, saved outcome, and absence of the API key from these artifacts. Application code did not change, so the application test suite was not rerun.

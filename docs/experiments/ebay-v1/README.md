# eBay search trial

The antique-sofa search returned useful listings. Three of its first six results visually resemble the reference sofa, and all six listing pages opened and showed New York pickup locations. This is promising evidence for eBay, but it is not a complete photo-search test.

Two requests ran on September 18, 2026. They reused the saved short phrases; neither uploaded a photo nor called Lens.

| Phrase | ZIP | Outcome | Time |
| --- | --- | --- | ---: |
| `green velvet sofa` | 94103 | HTTP 400: the API rejected `LH_PrefLoc=Domestic`. No listings were searched successfully. | 0.19 s |
| `antique sofa` | 10001 | HTTP 200 / Success: 60 distinct listing links, all with thumbnails and prices. | 2.52 s |

The first request used the “Domestic” value described in [SerpApi's documentation](https://serpapi.com/ebay-search-api). The API rejected that value. Before the second request, we recorded an [amendment](amendment.json) that removed only this optional parameter. Both requests used `show_only=LPickup`, their assigned ZIP as `_stpos`, and `ebay_domain=ebay.com`. The second response echoed its query, ZIP, and pickup filter correctly.

The API returned 60 items despite `_ipg=25`. Its reported total was 1,600; we inspected only the returned first page and do not treat that total as a verified inventory count. No pagination or additional searches ran.

## First six results

These are in provider order, without reranking or substituting better results. Visual judgments compare the listing photos with the [ornate sofa reference](../feasibility-v1/photos/ornate-sofa.jpg).

| Position | Listing | Price | Pickup ZIP on listing | Similar to reference? |
| --- | --- | ---: | --- | --- |
| 1 | [Lillian August sofa](https://www.ebay.com/itm/287516957646) | $700 | 10001 | No: plain upholstered sofa without the reference's carved frame. |
| 2 | [Harden Mission settee](https://www.ebay.com/itm/313764202325) | $2,500 | 10001 | No: straight wooden slats and angular shape. |
| 3 | [W. & J. Sloane loveseat](https://www.ebay.com/itm/377462840300) | $475 | 10010 | Yes: curved exposed wood frame and patterned upholstery. |
| 4 | [W. & J. Sloane French Louis sofa](https://www.ebay.com/itm/377462853156) | $1,000 | 10010 | Yes: curved wood frame, patterned upholstery, and similar overall shape. |
| 5 | [West Elm Peggy sectional](https://www.ebay.com/itm/277700664931) | $12,500 | 10011 | No: modern sectional with a different shape and style. |
| 6 | [Carved antique sofa](https://www.ebay.com/itm/286693235113) | $850 | 10022 | Yes: carved frame, curved back, and patterned upholstery. |

All six pages opened, displayed the corresponding prices, and offered local pickup. Pickup cities and ZIPs came from each page's “See map” link, which pointed to New York, NY. The browser's distance text used its own default destination ZIP, so it was not used to judge distance from 10001. No seller was contacted, and availability is not guaranteed.

## What this establishes

eBay returned individual listing links, photos, and prices without Google Images or Craigslist URL filtering. The first six items included three visually relevant results in the requested city.

Location remains a limitation for the app: every API item said only “Located in United States,” and the retained shipping field was empty. The more precise pickup ZIPs above were checked manually on listing pages. These observations do not establish a reliable radius filter or show how to populate city labels within the two-call design.

The green-sofa case has no successful eBay result yet. We also have not tested a fresh Lens-to-eBay flow or the remaining reference photos. The app, mockup, and chosen production marketplace have not been changed.

## Evidence and allowance

- [Frozen requests and limits](manifest.json), plus the second-request [amendment](amendment.json).
- Sanitized observations: [modern sofa](modern-sofa.json) and [ornate sofa](ornate-sofa.json).
- [Manual listing checks](manual-checks.json).
- The existing SQLite ledger reserved each request before dispatch, including the rejected request. Both count toward the local experiment limit.

Combined experiment usage is **12 of 15 search attempts**. Three remain unused. The separate two-attempt final deployment allowance is untouched. Earlier manifests, observations, scores, and ledger rows are unchanged.

Offline checks covered URL allowlisting, tracking-parameter removal, price extraction, credential redaction, frozen source hashes, ledger reservations, and saved-result consistency. No application code changed, so the application test suite was not rerun.

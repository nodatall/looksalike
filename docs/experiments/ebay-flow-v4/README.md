# Ornate-sofa retest

On September 28, 2026, the ornate sofa returned four relevant items out of six in **12.8 seconds**, compared with two in the earlier run. Two are close matches; two qualify mainly by patterned upholstery or traditional style. All six were complete sofas and their listing pages opened.

This is one focused retest. It does not establish a new five-photo score or prove general visual accuracy. The public app is not connected to this flow yet.

## What changed

- Lens phrases with only a category or broad style now use Venice. A recognized color or material keeps the Lens path.
- The prepared query carries its furniture category separately.
- Eligible US listings are checked for wrong furniture types, parts, covers, replacement cushions and miniatures before taking six. Promoted listings use the same checks. Remaining provider order is unchanged.

The model stayed `qwen3-vl-235b-a22b`. Lens returned **“sofa”** this time, and Venice produced **“dark wood frame red patterned upholstery sofa.”** The previous run returned “vintage sofa.” Because the live Lens response changed, this run exercised the bare-category fallback; offline tests and saved-response replay verify the new style-only rule. The two live runs are not a controlled comparison of that rule alone.

## Displayed results

The first six filtered items were reviewed in their original order against the reference photo. The existing criterion accepts the same furniture category with similar shape, material or style; it requires at least three accessible matches within 55 seconds.

| Item | Judgment |
| --- | --- |
| [Red floral carved-frame sofa](https://www.ebay.com/itm/800178300673) | Close: carved brown frame, curved back and red floral fabric. |
| [Plain red sofa](https://www.ebay.com/itm/377479915878) | No: straight, armless shape and plain fabric. |
| [Patterned sofa](https://www.ebay.com/itm/178536059984) | Partial: ornate patterned fabric and dark frame; boxier shape. |
| [Red/beige damask sofa](https://www.ebay.com/itm/398254415262) | Partial: traditional patterned fabric; no exposed carved frame. |
| [Blue floral scroll-arm sofa](https://www.ebay.com/itm/366424855907) | Close style/shape: wood frame and scroll arms; different color. |
| [Green-cushion wood-frame sofa](https://www.ebay.com/itm/397975991247) | No: casual frame and loose cushions differ from the reference. |

The provider returned 72 rows. Two lacked an explicit US location. Of the remaining 70, the title filter kept 15 and rejected 43 wrong categories, seven accessories/parts, three mixed-category titles, one miniature and one other item. The first six retained provider positions 1, 5, 6, 8, 9 and 10. Title checks cannot measure visual similarity or verify seller claims.

## Calls and checks

One upload, one Lens search, one Venice call and one eBay search completed without retries. Venice took about 4.1 seconds. Its recorded usage was 1,821 input and 38 output tokens; the frozen published token rates imply about $0.00046, not a billing receipt. The reserved cap was $0.03. The account check confirmed **212 SerpApi searches remaining**; recorded development attempts total 41.

The shared deadline remained 55 seconds. eBay requests omitted the country filter; returned rows required an explicit US location. No new model, description input or geographic setting was introduced.

- `bin/check` passed: 89 Ruby tests, 1,239 assertions, eight JavaScript tests, build, lint, dependency audits and security checks.
- The disposable runner passed 13 offline tests and 82 assertions with network calls blocked.
- [Saved-result replay](saved-result-replay.json) removes the previously seen sofa table, rugs and replacement chair legs, while retaining the four complete chairs.
- Scoped code review found a replacement-cushion gap. The narrow fix and regression cases passed targeted rereview.
- Frozen source hashes and 19 historical ledger tables verified unchanged. Saved outcome and judgment match the ledger; all four stage reservations are complete. No configured provider key was found in the new JSON evidence.

## Evidence

[Manifest](manifest.json) · [Full normalized outcome and rejection reasons](ornate-sofa.json) · [Manual judgments](ornate-sofa-judgment.json) · [Account after run](account-after.json) · [Verification](verification.json).

Earlier [five-photo results](../ebay-flow-v3/README.md) and their scores remain unchanged. The previous policy sources are preserved under `../query-v4/`. The manifest hashes the ignored manual operator runner and offline probe; those are local experiment tools, not public routes or production quota enforcement.

# Five-photo recheck

The September 29, 2026 recheck **failed the release criterion**: two photos passed, two failed, and the dresser remained untested. The experiment stopped after its second failure, as required. Feature work must wait for a repair and a new bounded recheck.

Each photo needed at least three relevant, distinct, accessible items among its original first six within 55 seconds. Relevance means the same furniture category with similar shape, material or style. Items were reviewed in provider order without replacing weak results.

| Photo | Result | Relevant and accessible | Time | Evidence |
| --- | --- | --- | --- | --- |
| Ornate sofa | Passed | 6 of 6 | 12.54 s | [Outcome](ornate-sofa.json), [judgment](ornate-sofa-judgment.json) |
| Modern sofa | Passed | 4 of 6 | 7.25 s | [Outcome](modern-sofa.json), [judgment](modern-sofa-judgment.json) |
| Dining chair | Failed | 2 of 6 | 11.49 s | [Outcome](dining-chair.json), [judgment](dining-chair-judgment.json) |
| Coffee table | Failed before eBay | 0 items shown | 11.85 s | [Outcome](wood-table.json), [judgment](wood-table-judgment.json) |
| Dresser | Untested after stop | — | — | No calls or judgment |

## Why two cases failed

The chair query was **“light wood finish turned spindle legs chair.”** Four of its first six items were loose chair spindles. They passed the title filter because it has no rule for these part descriptions. The other two were complete chairs and qualified mainly by material or traditional style. This was a filtering failure; eBay returned listings.

Lens identified the table as **“farmhouse coffee table.”** The current rule sends style-only phrases to Venice. Venice returned `not_furniture` with HTTP 200 and a completed response, so the flow stopped before making an eBay search. This is a photo-classification failure. It says nothing about available table inventory.

The table photo shows a large foreground table with bright vases and a bowl on top. The prompt already asks for the main furniture item, but does not explicitly tell the model to ignore decorations. The saved answer contains no rationale, so decorations are a possible explanation rather than a confirmed cause.

## Smallest proposed repairs

1. Reject titles describing **“spindle(s) for chair(s)”** or **“chair spindles.”** Preserve complete-chair wording such as “spindle back chair” and “spindle slatback dining chair,” and features after “with.” A blanket ban on “spindle” would discard real chairs.
2. Clarify the existing vision instruction: **“Ignore decorative objects placed on furniture, including vases and bowls. Choose the complete furniture item in the foreground.”** Keep the same model, output schema, deadline and single-call limit. A fresh test must establish whether this helps; the saved response cannot verify a changed prompt.

An offline, proposal-only replay removed the four observed loose-part false accepts while keeping both manually confirmed complete chairs. It retained provider order and changed the chair's proposed first six positions from `1, 2, 4, 5, 6, 7` to `4, 6, 9, 10, 11, 12`. The newly exposed four items were not manually scored, so this replay does **not** turn the failed case into a pass. No production rule or frozen result was changed.

## Calls and limits

The stopped batch used **seven SerpApi searches**: four Lens searches and three eBay searches. It also used four uploads and three Venice calls, reserving **$0.09** total for Venice. That reservation is a spending cap, not a billing receipt. There were no retries. The separate two-search deployment reserve was not used. The free account check confirmed 205 SerpApi searches remaining; recorded development searches total 48.

The model remained `qwen3-vl-235b-a22b`. eBay requests omitted country, ZIP and pickup filters; accepted rows required an explicit “Located in United States” field. The shared deadline stayed 55 seconds. All four completed cases finished within it.

The ignored operator runner passed 17 offline tests and 140 assertions before dispatch. The separate saved-response spindle proposal passed three offline tests and 16 assertions with network calls blocked. These checks cover the experiment controls and proposed title exclusions, not public UI behavior or new live model accuracy.

## Evidence and limits

[Manifest](manifest.json) · [Manifest checksum](manifest.sha256) · [Frozen source copies](source/) · [Account after run](account-after.json) · [Verification](verification.json).

The manifest records the five fixed photos, policy versions, Git baseline, source copies and hashes of all 22 prior ledger tables. Earlier [five-photo scores](../ebay-flow-v3/README.md) and the [focused ornate-sofa retest](../ebay-flow-v4/README.md) remain unchanged.

The two passing cases include partial matches. Four ornate-sofa items were judged close and two mainly matched style or material. Modern-sofa matches include different colors, upholstery and silhouettes; two of its first six were unrelated. Title filtering removes some ineligible items but does not rank visual similarity or verify seller claims. Listing access was checked at review time and may change. This stopped batch provides no new result for the dresser and no evidence of a five-photo pass.

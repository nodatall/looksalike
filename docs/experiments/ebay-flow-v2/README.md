# Photo-to-eBay comparison after the query repair

September 25, 2026. **The repair fixes the saved category errors, but the fresh search-quality test still fails.** Three photos ran: one passed and two failed. The batch stopped after the second failure; the coffee table and dresser were not run.

| Reference | Fresh phrase | Relevant, accessible items among first six | Total time | Result |
| --- | --- | --- | --- | --- |
| Ornate sofa | sofa | 0/6 | 9.39 s | Fail |
| Modern sofa | green velvet sofa | 3/6 | 6.03 s | Pass |
| Wooden dining chair | chair | 0/6 | 9.93 s | Fail |
| Coffee table | Not run | Not scored | — | Stopped |
| Dresser | Not run | Not scored | — | Stopped |

All executed provider calls succeeded. There were no timeouts, retries, or rescue searches. Every scored listing page opened. The modern-sofa pass includes one close green match, one orange sofa with similar shape and velvet upholstery, and one weaker gray velvet match with a different shape. The frozen criterion allows material similarity; this is not three close green matches.

## What changed, and what remains wrong

The [offline replay](../query-v3/replay.json) preserved both earlier sofa phrases, changed “cabinet” to “chair,” and preserved “coffee table.” That confirms the code repair on the saved text.

Fresh Lens titles were different. For the ornate sofa, seven titles voted for sofa, but no recognized trait occurred in two supporting titles. The previous “antique sofa” became just **sofa**. eBay returned modern upholstered sofas, a beanbag, and a Chesterfield rather than items with the reference's carved frame and patterned upholstery. Running the preserved v2 policy on these new excerpts also produces “sofa”; this failure is not evidence that the new voting rule alone caused the lost style.

The chair correctly became **chair**, with three supporting titles instead of the one cabinet mention. However, only one supporting title mentioned antique or wood. The first six eBay results were office or gaming chairs. Selecting the broad category is insufficient to preserve the reference's material and shape.

Four of the first six items in each case were sponsored. They remained in provider order. These results do not isolate the effect of advertising, ranking, or inventory, and no post-hoc filtering changed the score.

The coffee-table repair is verified only on saved Lens text. The live batch stopped before that photo under the unchanged two-failure rule.

## Smallest proposed next change

When Lens yields only a broad type such as “chair” or “sofa,” ask the visitor for a short description before spending the marketplace search. For this chair, “wooden dining chair” would express information visible in the photo but missing from the selected phrase. This would change the approved one-click flow, so it is a proposal, not an implemented feature or a proven quality fix.

A description still needs a bounded search test. Do not claim that adding it will pass, keep expanding the vocabulary to fit these photos, replace the failed cards, or silently score revised queries as this experiment.

## Method and usage

The [manifest](manifest.json) and [checksum](manifest.sha256) froze the new query code, prepared photos, operator, previous evidence, and ledger baseline before any requests. Query policy is `furniture-query-v3`: first eight titles, one vote per type per title, unique winner with at least two votes, preserved compounds, and repeated traits from supporting titles. Weak recognition skips eBay even if a related-query suggestion exists.

Each completed case used one image upload, one Lens search, and one eBay search. eBay received no country, ZIP, or pickup filter. Eligible rows needed explicit US location, a title, thumbnail, and valid item URL; duplicates were removed, then the first six kept in provider order. The pass criterion remained at least three relevant, distinct, accessible listings within 55 seconds in four of five cases. Manual page review was separate from request timing.

The account check confirmed **230 searches remaining** before dispatch. This batch used **six searches and three uploads**, below its cap of ten searches and five uploads. Recorded development usage is now **29 searches**, including the earlier 23. The remaining account balance was not refreshed. No requests ran for the coffee table or dresser, and the separate two-search deployment reserve is untouched.

## Evidence and checks

| Case | Sanitized response | Manual judgment |
| --- | --- | --- |
| Ornate sofa | [Response](ornate-sofa.json) | [Judgment](ornate-sofa-judgment.json) |
| Modern sofa | [Response](modern-sofa.json) | [Judgment](modern-sofa-judgment.json) |
| Dining chair | [Response](dining-chair.json) | [Judgment](dining-chair-judgment.json) |

The query and flow tests passed: 13 tests, 122 assertions. The disposable operator checks passed: five tests, 65 assertions, covering accounting, deadlines, order, filters, restart guards, the two-failure stop, and skipped marketplace calls after weak recognition. The full `bin/check` passed: 63 Ruby tests with 621 assertions, eight JavaScript tests, style, dependency audits, Brakeman, build, and Rails loading. Ordinary checks made no paid calls.

Post-run verification matched all three outcomes and judgments to the ledger, checked parameters and scoring, confirmed the 62 frozen files and 13 historical table hashes, and verified that the preserved query-v2 source matches its old hash. A further coffee-table execution was rejected by the two-failure guard before network access, with all 16 old and new table hashes unchanged. The new comparison uses separate ledger tables. The operator and local ledger remain ignored development artifacts, not a portable public replay harness. Sanitized evidence excludes credentials and private upload references.

The app still does not run live searches. Search quality remains the blocker to the remaining app, example, and deployment work; passing code checks does not satisfy that gate.

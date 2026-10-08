# Full photo-to-eBay comparison

September 20, 2026. **Search quality failed: two photos passed and two failed.** All provider calls completed within the 55-second limit. The batch stopped after its second failure, leaving the fifth photo untested.

| Reference | Extracted phrase | Relevant, accessible items among first six | Total time | Result |
| --- | --- | --- | --- | --- |
| Ornate sofa | antique sofa | 4/6 | 16.26 s | Pass |
| Green modern sofa | green velvet sofa | 3/6 | 7.84 s | Pass |
| Wooden dining chair | cabinet | 0/6 | 8.59 s | Fail |
| White storage coffee table | white farmhouse table | 1/6 | 30.11 s | Fail |
| Dresser | Not run | Not scored | — | Stopped |

The green-sofa result contains two close matches and one weaker match: a black velvet sofa counted because it shares the category and material. This follows the frozen criterion; it does not mean three close green-sofa matches. All 24 scored listing pages were accessible when checked. Accessibility does not establish availability or shipping eligibility.

## Why it failed

The chair's first Lens title contained the business name “Kramer Furniture and Cabinet.” The extractor chose **cabinet**, although two of the first eight titles mentioned chairs and only one mentioned a cabinet. eBay then returned cabinets.

Three of the coffee table's first eight Lens titles said **coffee table**. The extractor kept only **table**, adding “white farmhouse.” Of the first six eligible results, one was a coffee table; the others were a lamp, two TV stands, and two dining tables.

These are phrase-extraction failures. The four successful eBay responses each contained 60 items. This batch does not show a provider outage or a shortage of marketplace inventory.

## Smallest proposed repair

Choose the furniture category supported by multiple Lens titles rather than the first category word in one title. Preserve common names such as “coffee table” instead of reducing them to “table.” First replay the saved Lens excerpts offline, including the two passing sofa cases. Then freeze the revised rules and run a new bounded comparison with unchanged scoring.

Do not rescore this batch, replace poor cards, or add rescue queries. Sponsored results stayed in provider order; four of the green-sofa cards were sponsored. Any change to ordering needs a separately recorded experiment.

## Frozen method and cost

The [manifest](manifest.json) and [checksum](manifest.sha256) were saved before dispatch. Each case used its existing prepared photo, one upload, Lens with `type=all`, and one eBay search using `furniture-query-v2`. The eBay request used `ebay_domain=ebay.com` and `_ipg=25`, without a country, ZIP, or pickup filter. Returned items had to supply an explicit US location, title, thumbnail, and valid eBay item link. Prices were optional. Duplicates were removed; the first six eligible items retained provider order.

The pass rule was at least three relevant, distinct, accessible listings among the first six, within 55 seconds, for four of five photos. Relevance meant the same furniture category and similar shape, material, or style. Timings include photo validation, upload, Lens, and eBay; manual review happened afterward. The two-failure stop made a batch pass impossible after the coffee table.

An account check confirmed 238 searches remaining before the batch. This run used **eight searches and four uploads**, with no retries, against a cap of ten searches and five uploads. Combined recorded development usage is **23 searches**, including the earlier 15. The remaining account balance has not been refreshed. Previous ledgers, scores, and frozen files remain unchanged.

## Evidence and verification

| Case | Sanitized response | Manual judgment |
| --- | --- | --- |
| Ornate sofa | [Response](ornate-sofa.json) | [Judgment](ornate-sofa-judgment.json) |
| Modern sofa | [Response](modern-sofa.json) | [Judgment](modern-sofa-judgment.json) |
| Dining chair | [Response](dining-chair.json) | [Judgment](dining-chair-judgment.json) |
| Coffee table | [Response](wood-table.json) | [Judgment](wood-table-judgment.json) |

The disposable operator lives in ignored `agent-scratch/`; its exact hashes are in the manifest. The local SQLite ledger retains reservations, outcomes, scores, and the account check. Public evidence contains sanitized fields and Lens excerpts, not complete raw provider responses or private upload IDs. These records document this run; the ignored operator and ledger are not a portable public reproduction harness.

Offline operator checks passed: four tests and 61 assertions covered accounting, ordering, filters, deadlines, restart guards, and the two-failure stop. Focused application checks passed: 28 tests and 147 assertions. Post-run verification matched all 48 frozen files, all ten historical table hashes, the four saved outcomes and judgments, stage parameters and timings, and pass arithmetic. Attempting the dresser with network access forbidden stopped before dispatch; all ledger tables remained unchanged. The configured key and private upload identifiers were absent from the experiment evidence.

The full `bin/check` also passed after refreshing the dependency-advisory cache: Ruby and JavaScript style, dependency audits, Brakeman, build, Rails loading, eight JavaScript tests, and 64 Ruby tests with 585 assertions. These checks made no paid provider calls.

Feature implementation and deployment remain blocked on the quality criterion. No application search flow changed in this experiment.

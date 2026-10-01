# Furniture query v3

The approved repair chooses a furniture type supported by multiple Lens titles and preserves names such as “coffee table.” It replaces the first-word rule that selected a cabinet for a chair and reduced a coffee table to a generic table.

## Rule

Read the first eight visual-match titles, in provider order. Normalize common synonyms and plurals. Each title votes at most once for each recognized furniture type. Match known compound types before their generic words; “coffee table” does not also vote for “table.” Only adjacent words can form a compound.

Choose the unique type with the most votes, with at least two supporting titles. Ties, single mentions, and unknown types return weak recognition and skip the marketplace request. Related-query suggestions cannot override this rule.

Add at most two familiar traits from distinct groups: color, material, and style. Each trait must occur in at least two titles supporting the chosen type. Select first-seen traits as before and display them in color/material/style order. The rule does not infer missing details from the photograph.

The finite compound vocabulary is coffee table, dining table, side table, end table, console table, bedside table, dining chair, office chair, rocking chair, and bar stool. Generic types keep their existing vocabulary. Ranking tokenization is unchanged.

## Saved-response replay

| Reference | Previous phrase | Revised phrase |
| --- | --- | --- |
| Ornate sofa | antique sofa | antique sofa |
| Modern sofa | green velvet sofa | green velvet sofa |
| Dining chair | cabinet | chair |
| Coffee table | white farmhouse table | farmhouse coffee table |

The [replay](replay.json) uses the four saved Lens excerpts from the earlier eBay comparison and makes no API calls. “White” disappears from the table phrase because only one supporting coffee-table title includes it; the other white mention describes wallpaper. This replay proves the extraction change on saved text, not search quality on new photos.

[The previous query source](search_query_v2.rb) preserves the exact file hash recorded by `ebay-flow-v1`. Its original results, manifest, and ledger remain unchanged. To run that historical operator unchanged, use Git revision `a50455c`; it deliberately rejects the new query source. The new comparison uses a separate `ebay-flow-v2` manifest and ledger tables.

The fresh comparison keeps the same five photos, first-six ordering, US-location checks, 55-second deadline, and pass criterion. It allows up to ten searches and five uploads, with no retries, and stops after two failed photos. A fresh account check must leave two searches reserved for deployment. No live calls are made by ordinary tests.

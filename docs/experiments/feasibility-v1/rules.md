# Frozen rules: feasibility-v1

Status: not run. These rules were fixed before any scored upload or search. The examples in tests are synthetic policy inputs, not search evidence.

## Recognition: furniture-query-v1

`SearchQuery` owns the category aliases and stopword lists. Their exact source file is hashed in the manifest. Category order is sofa, loveseat, chair, armchair, recliner, chaise, sectional, table, desk, dresser, cabinet, bookcase, shelf, bed, nightstand, bench, stool, ottoman. List order does not override source order: the earliest qualifying category token wins.

Normalize valid string inputs by Unicode NFKD decomposition, lowercase, removal of combining marks, then ASCII `[a-z0-9]+` tokenization. Punctuation, hyphens, apostrophes, and non-ASCII letters remaining after normalization separate tokens. Reject tokens shorter than two characters, all-digit tokens, and these stopwords:

`a an and are as at be by for from in is it of on or that the this to with your you buy sale sell selling used new furniture craigslist item items near set pair piece pieces s`

Only category words are singularized: each category except bench and shelf plus `s` maps to that category. Benches maps to bench and shelves maps to shelf; the misspellings benchs and shelfs are not category aliases. Additionally, couch/couches map to sofa and bookshelf/bookshelves to bookcase. There is no general stemming, semantic synonym expansion, LLM interpretation, or sample-specific tuning.

1. Inspect `related_content` in provider order. Select the first object's nonempty string `query` containing a whole category token after normalization. Choose its first category. Remove other category tokens, stopwords, and duplicate words while preserving first-seen order. Take at most eight tokens. If the selected category occurs after token eight, keep the first seven plus that category so the phrase cannot lose its furniture category.
2. Otherwise inspect exactly the first eight `visual_matches` positions. Missing/malformed titles occupy their original positions and contribute no tokens. Choose the first category encountered in provider/title-token order. Count each normalized descriptive token at most once per title. Output the chosen category first, followed by non-category tokens present in at least two titles, in first-seen order, capped at eight words total. Other categories never enter the phrase.
3. No category returns a nullable phrase and `weak_recognition`. A category alone is usable. No manual query editing, extra request, rescue query, or fallback after provider failure is permitted.

## Routes and request parameters

Each case starts with a separate binary multipart `POST https://serpapi.com/image` of its frozen JPEG through the shared client. Authentication and the transient image reference are runtime-only and never written to this manifest or public trace. The upload counts separately from searches.

- First candidate, `lens_only`: `GET /search.json`, `engine=google_lens`, `type=visual_matches`, `country=us`, `hl=en`, `q=site:<exact selected hostname>`, and the runtime upload reference. Use `visual_matches[].link`. No phrase is required and no ranking replaces provider order.
- Only if Lens-only fails the criterion, candidate `lens_then_images`: Lens `engine=google_lens`, `type=all`, `country=us`, `hl=en`, and the runtime upload reference. Extract the phrase above. Then Images `engine=google_images`, `q=<phrase> site:<exact selected hostname>`, `location=<frozen canonical origin>`, `gl=us`, `hl=en`. Use `images_results[].link`. Do not use related-query links, shopping results, image/original URLs, undocumented ZIP parameters, automatic retries, or extra pages.

The same 55-second monotonic deadline covers server validation, upload, and all searches. No async polling or response redirects. The two-search route stops with weak recognition if no phrase is available. Maximum searches per case: one for Lens-only and two for Lens-then-Images; upload does not increment those search counts.

## Listings: craigslist-listings-v1

The normalizer takes an injected approved-host catalog and the resolved location. The selected host must independently occur in that catalog and match a single lowercase `*.craigslist.org` area hostname. Policy code performs no network requests or data-file loading.

Read destinations only from `link`. Require an HTTP or HTTPS URL of at most 2,048 bytes, with no whitespace, backslash, userinfo, or nondefault port. Explicit HTTP:80 and HTTPS:443 are accepted. Host comparison is case-insensitive but must exactly equal the selected approved hostname; trailing-dot, alternate-area, subdomain-suffix, and `www` hosts fail.

Accept only these legacy individual-listing paths, with lowercase three-letter area/category segments, optional lowercase alphanumeric/hyphen slug, and a 1–20 digit listing ID:

- `/category/ID.html`
- `/subarea/category/ID.html`
- `/category/d/slug/ID.html`
- `/subarea/category/d/slug/ID.html`

The literal regex is in the hashed normalizer source. Search/category pages, percent-encoded or nonnumeric IDs, traversal segments, and canonical `www.craigslist.org/view/...` links are rejected. Such `/view` URLs lack regional evidence; this experiment does not weaken that rule. Canonical output uses HTTPS and the lowercase approved hostname; remove destination query and fragment. Deduplicate by numeric listing ID (leading zeros do not create a new identity).

Require a nonblank string title of at most 300 characters / 1,200 input bytes after whitespace normalization, with remaining control characters rejected. Require a valid HTTP(S) thumbnail with the same URL-size, credentials, and default-port checks; its host can differ. Reject thumbnail query parameter names (case-insensitive, hyphens normalized to underscores) api_key, apikey, access_token, token, secret, client_secret, authorization, auth, signature, sig, key, policy, key_pair_id, awsaccesskeyid, googleaccessid, and any x_amz_ or x_goog_ prefix. These are explicit credential/signed-auth exclusions. Keep other query parameters, including Google thumbnail q, and remove the fragment. Never fall back to `image` or `original` when `link` or `thumbnail` is missing.

Validate URL, then metadata, then deduplicate. Thus an incomplete early duplicate does not disqualify a later complete occurrence. Keep the first complete occurrence of an ID before ranking. Lens-only retains provider order. Lens-then-Images ranks by the count of unique normalized query/title token intersections, descending, with original provider index breaking ties. Cap the ordered output at six.

Retain only the documented Lens `price.value` string, bounded to 80 characters / 320 input bytes and normalized like a title. Current documented `images_results` has no price field; separate shopping results are not used. Neither current result schema documents a listing city or neighborhood, so location is always `Craigslist area: <selected area name>`. Do not infer price, location, availability, or similarity percentage from title, source, URL slug, or region. Adding a new supported metadata schema later requires a policy version change.

Counts partition processing into `input`, `rejected_url`, `missing_metadata`, `duplicates`, `eligible`, `limited`, and `displayed`: input equals rejected_url + missing_metadata + duplicates + eligible; eligible equals limited + displayed. Summaries contain these counts and normalized listings only, not rejected URLs or raw provider records.

## Budget and scoring

Use the five photo/ZIP pairs in manifest order, unchanged for both candidates. A case passes only if at least three of the first six returned listings are relevant, distinct, accessible, and on the selected area within 55 seconds. Relevant means the same furniture category and similar shape, material, or style. Judge manually without replacement or rescue queries.

An approach passes at four of five cases. Stop an approach after two failed photos; remaining cases are untested. Test Lens-only first and use it if it passes. Otherwise test Lens-then-Images. The cumulative comparison budget is at most 15 attempted searches, including uncertain outcomes; a separate final deployed smoke check reserves at most two further attempts. A durable pre-dispatch ledger and account allowance check remain required before any paid work. If neither approach passes, stop feature work and report the evidence.

## Provenance and change control

Use the exact five browser-prepared JPEGs. Their `jpeg-v1` recipe, source-byte hashes, output-byte hashes, dimensions, quality, and reported browser user agent are in the manifest. Source photo sizing is part of provenance; two oversized original downloads were replaced with 2,400×1,600 downloads of the same licensed photo before preprocessing.

`script/verify_experiment.rb` checks the manifest sidecar, frozen code/data/photo hashes, server image acceptance, and current ZIP/area/origin against the recorded values. Run it before any later dispatch. The manifest is not a result log: append future measured evidence separately. Changing a frozen input, policy, request contract, or location mapping requires a new manifest version and invalidates affected comparisons; never silently refresh hashes to bless drift.

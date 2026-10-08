# Offline location data

`LocationResolver.resolve("02108")` validates a ZIP and returns one approximate Craigslist area and its supported Google Images search origin. It is plain Ruby: no database, network, geocoding, upload, or allowance reservation. The location step must complete before those later search operations.

The class loads `postal_codes.tsv` and `areas.json` once when loaded in each process. They stay outside browser assets. The returned immutable record contains the original ZIP, postal place/country/state/coordinates, approved hostname, area name/ID/center, canonical SerpApi origin, selection rule, mapping version, and query version. Call `to_h` when constructing a response. `InvalidZip` means the input is not a string of exactly five ASCII digits; `UnmappedZip` means the formatted ZIP has no supported mapping. Neither error substitutes a default area.

## Selection rules

1. Require an admitted postal record; preserve leading zeros.
2. Apply an explicit ZIP override, then a country override. The current ZIP override table is empty. GU, PR, and VI each use their own approved area.
3. For states/DC, choose the nearest of the 413 US centers using haversine distance, with hostname as the equal-distance tie-break. State borders do not constrain metropolitan areas: Hoboken `07030`, for example, selects New York.
4. Reject unsupported countries and missing override targets. No host is constructed from visitor input.

This is an approximate area selector, not a Craigslist boundary map or a listing-distance guarantee. Rural and Alaska centers can be far away. The SerpApi city origin adds search context; the selected approved Craigslist hostname remains the regional restriction.

`mapping_version` is `2026-09-17-v1`. `LocationResolver::QUERY_VERSION` is `craigslist-area-v1`, identifying the current exact selected-host query restriction. Later cache/experiment code must retain both versions and update the relevant version when its rules change.

## Snapshot and coverage

The snapshots were downloaded September 17, 2026. Exact source URLs, SHA-256 hashes, archive/text sizes, GeoNames member dates, importer/override hashes, exclusion counts, and generated artifact hashes are in `provenance.json`. Retrieval dates do not imply a publication date for Craigslist or SerpApi.

| Source | Admitted | Exclusions or limits |
| --- | ---: | --- |
| GeoNames US | 40,977 ZIPs across 50 states and DC | 511 blank-state APO/FPO rows and two Marshall Islands rows |
| GeoNames PR | 177 ZIPs | Uses `puertorico.craigslist.org` |
| GeoNames GU | 21 ZIPs | Uses `micronesia.craigslist.org` |
| GeoNames VI | 16 ZIPs | Uses `virgin.craigslist.org` |
| GeoNames AS | 0 | `96799` exists, but no verified Craigslist area |
| GeoNames MP | 0 | `96950`, `96951`, `96952` have no explicitly verified area mapping |
| UM | 0 | No separately published postal file or verified area mapping in the inspected sources |

The result contains **41,191 unique ZIPs and 416 areas**: 413 states/DC areas plus three territories. The two duplicated US source ZIPs, `96860` and `96863`, retain their ordinary HI rows; their blank-state FPO alternatives are excluded. Other military-only ZIPs, unknown ZIPs, and unsupported territories fail before paid traffic. The postal source is not proof that every currently assigned US ZIP is present.

The official [Craigslist directory](https://www.craigslist.org/about/sites) supplies the approved US section. Its own map script loads the [area catalog](https://reference.craigslist.org/Areas), which supplies host slugs, names, area IDs, countries, states, and representative center coordinates. All 416 directory slugs join that catalog; worldwide areas outside this section are excluded. The directory map also constructs the corresponding legacy regional hostnames.

The [SerpApi full supported-locations list](https://serpapi.com/locations.json), linked by its [Locations API documentation](https://serpapi.com/locations-api), contains 210,946 records in the imported snapshot. Import uses valid `City` entries only and restricts them to the same country and, for US areas, state. Two US city rows lack state metadata and are excluded. Runtime never loads this 66 MB source file.

Origins prefer normalized full Craigslist descriptions and their first slash/hyphen component, followed by short descriptions. Normalization handles punctuation, St/Saint, Ft/Fort, terminal state qualifiers, metro, and bay area. Duplicate names use distance, canonical name, then Google ID. Otherwise the nearest supported city is used. Five explicit overrides freeze San Francisco, New York, Chicago, Boston, and Seattle for the experiment. The snapshot produces 316 name matches, five overrides, and 95 nearest-city fallbacks; every area resolves. Per-area origin IDs, coordinates, rule, and distance are preserved in `areas.json`.

PR/GU/VI have 25/4/3 supported City entries respectively. Their selected origins are Manati, Barrigada, and Charlotte Amalie. Broad regions can select small cities: southwest Texas selects Presidio, 111.945 km from its regional center. Those choices follow the documented approximation.

## Reproduce the import

Use Python 3's standard library; there are no Python dependencies or automatic downloads. Place explicit downloaded snapshots in one directory using these filenames:

| Filename | Source |
| --- | --- |
| `looksalike-craigslist-sites.html` | `https://www.craigslist.org/about/sites` |
| `looksalike-areas.json` | `https://reference.craigslist.org/Areas` |
| `looksalike-serpapi-locations.json` | `https://serpapi.com/locations.json` |
| `looksalike-geonames-US.zip` | `https://download.geonames.org/export/zip/US.zip` |
| `looksalike-geonames-{AS,GU,MP,PR,VI}.zip` | Separate matching archives from `https://download.geonames.org/export/zip/` |

From the repository root:

```sh
python3 script/import_locations.py \
  --snapshots /path/to/downloaded-snapshots \
  --snapshot-date 2026-09-17 \
  --mapping-version 2026-09-17-v1
```

The default override input is `data/locations/overrides.json`; `--overrides` selects another explicit file. Use `--output /tmp/location-import-check` to compare a reimport without replacing bundled data. Reusing the same snapshots, overrides, script, version, and retrieval date produces byte-identical artifacts and provenance. The script validates source joins, admitted uniqueness, finite coordinates, state/DC coverage, and supported origins before writing. Source shape or matching failures stop the import rather than silently dropping areas.

The bundled runtime files total 1,788,778 bytes (1,588,909 postal TSV and 199,869 area JSON). TSV columns, without a header: ZIP, country, state, place, latitude, longitude. Source archives and the full supported-city catalog are not bundled.

## Attribution and URL compatibility

Postal data: [GeoNames](https://www.geonames.org/), [postal downloads](https://download.geonames.org/export/zip/), CC BY 4.0 as stated in the preserved `geonames-readme.txt`. The original README still contains a 3.0 link; it is retained verbatim. Display GeoNames attribution when the location/search explanation is made public. Data is provided without completeness or accuracy guarantees. Craigslist and SerpApi metadata retain source attribution here and in provenance; no separate reuse license was stated in the inspected metadata.

On September 17, 2026, two inspected legacy regional numeric `.html` listing URLs still redirected successfully with HTTP 200. Current Craigslist pages also publish `www.craigslist.org/view/d/.../<opaque-token>` links whose URLs lack regional evidence. The planned normalizer must continue accepting only the selected legacy hostname and reject canonical-only `www` links unless region is independently proven. This data import does not add runtime Craigslist fetching or relax that contract; the paid feasibility experiment still has to establish usable results.

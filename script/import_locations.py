#!/usr/bin/env python3
"""Import explicitly downloaded public snapshots. No network or third-party packages."""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import zipfile


STATES = set("AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY".split())
POSTAL_COUNTRIES = ("US", "AS", "GU", "MP", "PR", "VI")
TERRITORIES = {"GU", "PR", "VI"}
SOURCE_URLS = {
    "looksalike-areas.json": "https://reference.craigslist.org/Areas",
    "looksalike-craigslist-sites.html": "https://www.craigslist.org/about/sites",
    "looksalike-serpapi-locations.json": "https://serpapi.com/locations.json",
    **{f"looksalike-geonames-{country}.zip": f"https://download.geonames.org/export/zip/{country}.zip" for country in POSTAL_COUNTRIES},
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def coordinates(latitude, longitude):
    return all(isinstance(n, (int, float)) and not isinstance(n, bool) and math.isfinite(n) for n in (latitude, longitude)) and -90 <= latitude <= 90 and -180 <= longitude <= 180


def distance(latitude, longitude, other_latitude, other_longitude):
    lat, lon, other_lat, other_lon = map(math.radians, (latitude, longitude, other_latitude, other_longitude))
    h = math.sin((other_lat - lat) / 2) ** 2 + math.cos(lat) * math.cos(other_lat) * math.sin((other_lon - lon) / 2) ** 2
    h = min(1, max(0, h))
    return 6371 * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))


def normalize(name):
    name = name.lower().replace("&", "and")
    name = re.sub(r"\bst[.]?\s", "saint ", name)
    name = re.sub(r"\bft[.]?\s", "fort ", name)
    return re.sub("[^a-z0-9]", "", name)


def choose_origin(area, cities, override):
    candidates = []
    for raw in (area["Description"], area["ShortDescription"]):
        label = re.sub(r",\s*[A-Z]{2}(?:/[A-Z]{2})?$", "", raw)
        primary = re.split(r"\s*/\s*|\s*-\s*", label)[0]
        candidates.extend((label, re.sub(r"\s+(?:metro|bay area)$", "", label), primary, re.sub(r"\s+metro$", "", primary)))
    if override:
        candidates = [override]

    def order(city):
        return (distance(area["Latitude"], area["Longitude"], city["gps"][1], city["gps"][0]), city["canonical_name"], city["google_id"])

    for candidate in candidates:
        matches = [city for city in cities if normalize(city["name"]) == normalize(candidate)]
        if matches:
            chosen = min(matches, key=order)
            return chosen, "explicit_five_case_override" if override else "primary_name_match", round(order(chosen)[0], 3)
    require(not override, f"Unsupported origin override: {area['Hostname']} / {override}")
    require(cities, f"No supported city: {area['Hostname']}")
    chosen = min(cities, key=order)
    return chosen, "nearest_supported_city", round(order(chosen)[0], 3)


def fingerprint(path):
    content = path.read_bytes()
    return {"bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def run(args):
    sources = {name: args.snapshots / name for name in SOURCE_URLS}
    # Source reads and all validation precede output writes.
    source_metadata = {name: {"url": SOURCE_URLS[name], "downloaded_on": args.snapshot_date, **fingerprint(path)} for name, path in sources.items()}
    overrides = json.loads(args.overrides.read_text())
    postal_codes, state_names, postal_audit = {}, {}, {}
    readme = None
    for country in POSTAL_COUNTRIES:
        source_name = f"looksalike-geonames-{country}.zip"
        with zipfile.ZipFile(sources[source_name]) as archive:
            raw = archive.read(f"{country}.txt")
            rows = [line.split("\t") for line in raw.decode("utf-8").splitlines()]
            source_metadata[source_name]["postal_text_bytes"] = len(raw)
            source_metadata[source_name]["postal_member_date"] = "%04d-%02d-%02d" % archive.getinfo(f"{country}.txt").date_time[:3]
            if country == "US":
                readme = archive.read("readme.txt")
        reasons = Counter()
        for row in rows:
            require(len(row) == 12 and row[0] == country and re.fullmatch(r"[0-9]{5}", row[1]), f"Invalid {country} postal row")
            if country == "US" and row[4] not in STATES:
                reasons["military_blank_state" if not row[4] else "outside_states_dc"] += 1
                continue
            if country not in {"US", *TERRITORIES}:
                reasons["no_verified_craigslist_area"] += 1
                continue
            latitude, longitude = float(row[9]), float(row[10])
            require(coordinates(latitude, longitude), f"Invalid coordinates: {row[1]}")
            require(row[1] not in postal_codes, f"Duplicate admitted ZIP: {row[1]}")
            postal_codes[row[1]] = [country, row[4] if country == "US" else country, row[2], latitude, longitude]
            if country == "US":
                require(row[4] not in state_names or state_names[row[4]] == row[3], f"Conflicting state: {row[4]}")
                state_names[row[4]] = row[3]
        postal_audit[country] = {"source_rows": len(rows), "source_unique_zips": len({r[1] for r in rows}), "admitted": len(rows) - sum(reasons.values()), "excluded": dict(reasons)}
    require(set(state_names) == STATES, "Postal coverage must include all states and DC")

    html = sources["looksalike-craigslist-sites.html"].read_text()
    us_section = html.split('<a name="US"></a>')[1].split('<a name="CA"></a>')[0]
    directory_slugs = set(re.findall(r'https://www\.craigslist\.org/area/([a-z0-9]+)', us_section))
    catalog = json.loads(sources["looksalike-areas.json"].read_text())
    approved = [area for area in catalog if area["Hostname"] in directory_slugs]
    require(directory_slugs and len(approved) == len(directory_slugs), "Directory/catalog join is incomplete or duplicated")
    require({a["Region"] for a in approved if a["Country"] == "US"} == STATES, "Area coverage must include all states and DC")
    require(all(a["Country"] in {"US", *TERRITORIES} for a in approved), "Unexpected country in approved directory")

    locations = json.loads(sources["looksalike-serpapi-locations.json"].read_text())
    cities = []
    missing_state = []
    invalid_city_coordinates = 0
    for city in locations:
        if city["target_type"] != "City" or city["country_code"] not in {"US", *TERRITORIES}:
            continue
        gps = city.get("gps", [])
        if len(gps) != 2 or not coordinates(gps[1], gps[0]):
            invalid_city_coordinates += 1
            continue
        if city["country_code"] == "US" and city["canonical_name"].split(",")[-2] not in state_names.values():
            missing_state.append(city["canonical_name"])
            continue
        cities.append(city)

    areas = []
    for area in sorted(approved, key=lambda item: item["Hostname"]):
        require(coordinates(area["Latitude"], area["Longitude"]), f"Invalid area center: {area['Hostname']}")
        candidates = [city for city in cities if city["country_code"] == area["Country"] and (area["Country"] != "US" or city["canonical_name"].split(",")[-2] == state_names[area["Region"]])]
        origin, rule, kilometers = choose_origin(area, candidates, overrides["origin_overrides"].get(area["Hostname"]))
        areas.append({
            "hostname": area["Hostname"] + ".craigslist.org", "display_name": area["Description"], "area_id": area["AreaID"],
            "country": area["Country"], "state": area["Region"], "latitude": area["Latitude"], "longitude": area["Longitude"],
            "search_origin": origin["canonical_name"], "origin_google_id": origin["google_id"],
            "origin_latitude": origin["gps"][1], "origin_longitude": origin["gps"][0],
            "origin_rule": rule, "origin_center_distance_km": kilometers,
        })
    by_host = {area["hostname"]: area for area in areas}
    for country in TERRITORIES:
        host = overrides["country_overrides"].get(country)
        require(host in by_host and by_host[host]["country"] == country, f"Missing territory override: {country}")
    for country, host in overrides["country_overrides"].items():
        require(country in TERRITORIES and host in by_host and by_host[host]["country"] == country, f"Invalid country override: {country}")
    for code, host in overrides["zip_overrides"].items():
        require(code in postal_codes and host in by_host and postal_codes[code][0] == by_host[host]["country"], f"Invalid ZIP override: {code}")
    require(set(overrides["origin_overrides"]) <= directory_slugs, "Origin override references an unapproved area")

    args.output.mkdir(parents=True, exist_ok=True)
    catalog_output = {"mapping_version": args.mapping_version, "areas": areas, "zip_overrides": overrides["zip_overrides"], "country_overrides": overrides["country_overrides"]}
    write_json(args.output / "areas.json", catalog_output)
    # Headerless UTF-8 TSV: ZIP, country, state, place, latitude, longitude.
    postal_text = "".join("\t".join(map(str, [code, *record])) + "\n" for code, record in sorted(postal_codes.items()))
    (args.output / "postal_codes.tsv").write_text(postal_text, encoding="utf-8")
    (args.output / "geonames-readme.txt").write_bytes(readme)
    provenance = {
        "mapping_version": args.mapping_version, "snapshot_date": args.snapshot_date, "sources": source_metadata,
        "importer": {"path": "script/import_locations.py", **fingerprint(Path(__file__))},
        "overrides": fingerprint(args.overrides), "postal_coverage": postal_audit,
        "admitted_postal_codes": len(postal_codes), "states_and_dc": sorted(STATES),
        "areas": {"worldwide_source": len(catalog), "approved_directory": len(areas), "countries": dict(Counter(a["country"] for a in areas))},
        "origins": {"source_records": len(locations), "admitted_cities_by_country": dict(Counter(c["country_code"] for c in cities)), "excluded_missing_state": sorted(missing_state), "excluded_invalid_coordinates": invalid_city_coordinates, "rules": dict(Counter(a["origin_rule"] for a in areas))},
        "unsupported": {"AS": "96799: postal record exists; no verified Craigslist area", "MP": "96950, 96951, 96952: no explicitly verified area mapping", "UM": "No separately published GeoNames postal file or verified area mapping", "military": "Blank-state APO/FPO rows excluded; normal Hawaii rows for 96860 and 96863 retained", "MH": "Outside the states/DC and admitted territory scope"},
        "artifacts": {name: fingerprint(args.output / name) for name in ("areas.json", "postal_codes.tsv", "geonames-readme.txt")},
    }
    write_json(args.output / "provenance.json", provenance)
    print(json.dumps({"postal_codes": len(postal_codes), "areas": len(areas), "origin_rules": provenance["origins"]["rules"], "artifacts": provenance["artifacts"]}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshots", type=Path, required=True, help="Directory containing the named looksalike-* source snapshots")
    parser.add_argument("--snapshot-date", required=True, help="UTC retrieval date recorded during manual download, YYYY-MM-DD")
    parser.add_argument("--mapping-version", required=True)
    parser.add_argument("--overrides", type=Path, default=Path("data/locations/overrides.json"))
    parser.add_argument("--output", type=Path, default=Path("data/locations"))
    arguments = parser.parse_args()
    require(re.fullmatch(r"\d{4}-\d{2}-\d{2}", arguments.snapshot_date), "Expected YYYY-MM-DD snapshot date")
    run(arguments)

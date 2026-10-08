require "test_helper"

class LocationResolverTest < ActiveSupport::TestCase
  # Permanent table cases: a wrong region or accepted invalid ZIP can spend paid allowance.
  test "resolves the five frozen experiment locations with canonical supported origins" do
    {
      "10001" => [ "newyork", "New York,New York,United States" ],
      "94103" => [ "sfbay", "San Francisco,California,United States" ],
      "60601" => [ "chicago", "Chicago,Illinois,United States" ],
      "02108" => [ "boston", "Boston,Massachusetts,United States" ],
      "98101" => [ "seattle", "Seattle,Washington,United States" ]
    }.each do |zip, (host, origin)|
      result = LocationResolver.resolve(zip)
      assert_equal zip, result.zip
      assert_equal "#{host}.craigslist.org", result.hostname, zip
      assert_equal origin, result.search_origin, zip
      assert result.area_id.positive?
      assert result.latitude.finite? && result.longitude.finite?
      assert result.area_latitude.finite? && result.area_longitude.finite?
      assert_equal LocationResolver::CATALOG.fetch("mapping_version"), result.mapping_version
      assert_equal "craigslist-area-v1", result.query_version
    end
  end

  test "covers rural areas Alaska Hawaii duplicates DC and a state boundary" do
    {
      "59001" => "billings", "99501" => "anchorage", "99723" => "fairbanks",
      "99901" => "juneau", "99546" => "kenai", "96813" => "honolulu",
      "96860" => "honolulu", "96863" => "honolulu", "20001" => "washingtondc",
      "07030" => "newyork"
    }.each do |zip, host|
      assert_equal "#{host}.craigslist.org", LocationResolver.resolve(zip).hostname, zip
    end
    assert_equal "HI", LocationResolver.resolve("96860").state
    assert_equal "HI", LocationResolver.resolve("96863").state
    assert_equal "NJ", LocationResolver.resolve("07030").state
  end

  test "requires five ASCII digits and distinguishes malformed from unmapped ZIPs" do
    [ nil, 10001, "", "1000", "100001", "10001-1234", " 10001", "10001\n", "１２３４５", "abcde" ].each do |zip|
      assert_raises(LocationResolver::InvalidZip, zip.inspect) { LocationResolver.resolve(zip) }
    end
    %w[00000 99999 09001 96799 96950 96951 96952 96960 96970].each do |zip|
      assert_raises(LocationResolver::UnmappedZip, zip) { LocationResolver.resolve(zip) }
    end
    assert_not_requested :any, %r{https?://.*serpapi\.com/}
  end

  test "territories resolve only to their explicitly admitted local areas" do
    {
      "00601" => [ "PR", "puertorico", "Manati,Manati,Puerto Rico" ],
      "96910" => [ "GU", "micronesia", "Barrigada,Guam" ],
      "00801" => [ "VI", "virgin", "Charlotte Amalie,St. Thomas,U.S. Virgin Islands" ]
    }.each do |zip, (country, host, origin)|
      result = LocationResolver.resolve(zip)
      assert_equal country, result.country
      assert_equal "#{host}.craigslist.org", result.hostname
      assert_equal origin, result.search_origin
      assert_equal "country_override", result.mapping_rule
    end
  end

  test "has admitted postal records and approved areas across every state and DC" do
    states = %w[AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY].sort
    by_state = LocationResolver::POSTAL_CODES.select { |_, postal| postal[:country] == "US" }.group_by { |_, postal| postal[:state] }
    assert_equal states, by_state.keys.sort
    assert_equal states, LocationResolver::CATALOG.fetch("areas").select { |area| area["country"] == "US" }.map { |area| area["state"] }.uniq.sort
    approved_hosts = LocationResolver::CATALOG.fetch("areas").map { |area| area.fetch("hostname") }
    by_state.each_value do |records|
      assert_includes approved_hosts, LocationResolver.resolve(records.first.first).hostname
    end
  end

  test "distance wraps across the dateline and equal distances use hostname order" do
    resolver = fixture_resolver(areas: [ area("zeta", longitude: -179), area("alpha", longitude: 170) ], longitude: 179)
    assert_equal "zeta.craigslist.org", resolver.resolve("12345").hostname

    resolver = fixture_resolver(areas: [ area("zeta", longitude: -1), area("alpha", longitude: 1) ])
    assert_equal "alpha.craigslist.org", resolver.resolve("12345").hostname
  end

  test "explicit ZIP override wins over distance and changing ZIP preserves separate identity" do
    catalog = fixture_catalog([ area("near", longitude: 0), area("override", longitude: 50) ])
    catalog["zip_overrides"] = { "12345" => "override.craigslist.org" }
    postal = { "12345" => postal_code, "12346" => postal_code }
    resolver = LocationResolver.new(catalog: catalog, postal_codes: postal)
    first = resolver.resolve("12345")
    second = resolver.resolve("12346")
    assert_equal "override.craigslist.org", first.hostname
    assert_equal "zip_override", first.mapping_rule
    assert_equal "near.craigslist.org", second.hostname
    assert_equal "12345", first.zip
    assert_equal "12346", second.zip
    assert_equal "fixture-v1", first.mapping_version
  end

  test "unsupported country or missing override target cannot fall through to mainland" do
    catalog = fixture_catalog([ area("mainland") ])
    resolver = LocationResolver.new(catalog: catalog, postal_codes: { "96799" => postal_code.merge(country: "AS") })
    assert_raises(LocationResolver::UnmappedZip) { resolver.resolve("96799") }
    catalog["zip_overrides"] = { "12345" => "unapproved.craigslist.org" }
    resolver = LocationResolver.new(catalog: catalog, postal_codes: { "12345" => postal_code })
    assert_raises(LocationResolver::UnmappedZip) { resolver.resolve("12345") }
  end

  test "caller mutation cannot change a resolved ZIP or shared catalog strings" do
    zip = +"02108"
    result = LocationResolver.resolve(zip)
    zip.replace("10001")
    assert_equal "02108", result.zip
    assert_raises(FrozenError) { result.hostname.replace("newyork.craigslist.org") }
    assert_equal "boston.craigslist.org", LocationResolver.resolve("02108").hostname
  end

  private
    def area(name, longitude: 0)
      { "hostname" => "#{name}.craigslist.org", "display_name" => name, "country" => "US", "area_id" => 1,
        "latitude" => 0, "longitude" => longitude, "search_origin" => "#{name},United States" }
    end

    def postal_code(longitude: 0)
      { country: "US", state: "AK", place: "Test", latitude: 0, longitude: longitude }
    end

    def fixture_catalog(areas)
      { "mapping_version" => "fixture-v1", "areas" => areas, "zip_overrides" => {}, "country_overrides" => {} }
    end

    def fixture_resolver(areas:, longitude: 0)
      LocationResolver.new(catalog: fixture_catalog(areas), postal_codes: { "12345" => postal_code(longitude: longitude) })
    end
end

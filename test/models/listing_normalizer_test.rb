require "test_helper"

class ListingNormalizerTest < ActiveSupport::TestCase
  Location = Data.define(:hostname, :area_name)

  def location
    Location.new(hostname: "sfbay.craigslist.org", area_name: "SF bay area")
  end

  def normalize(items, route: "lens_only", query: nil)
    ListingNormalizer.new(approved_hostnames: [ "sfbay.craigslist.org" ]).call(items, location: location, route: route, query: query)
  end

  def item(id = "1234567890", title: "Oak chair", **overrides)
    { "title" => title, "link" => "https://sfbay.craigslist.org/sfc/fuo/d/san-francisco-chair/#{id}.html", "thumbnail" => "https://images.example/chair.jpg" }.merge(overrides.transform_keys(&:to_s))
  end

  test "accepts selected regional individual URLs and canonicalizes safe variants" do
    %w[https://sfbay.craigslist.org/fuo/1234567890.html http://sfbay.craigslist.org:80/sfc/fuo/1234567890.html https://SFBAY.craigslist.org:443/fuo/d/chair/1234567890.html?search=chair#photo].each do |url|
      result = normalize([ item(link: url) ])
      assert_equal 1, result.listings.length
      assert_match %r{\Ahttps://sfbay.craigslist.org/}, result.listings.first[:url]
      refute_match(/[?#]/, result.listings.first[:url])
    end
  end

  test "rejects unsafe destinations, regional ambiguity and non-listing paths" do
    urls = [
      "https://newyork.craigslist.org/fuo/123.html", "https://www.craigslist.org/view/d/chair/opaque-token",
      "https://sfbay.craigslist.org.evil.example/fuo/123.html", "https://sfbay.craigslist.org./fuo/123.html",
      "https://user:pass@sfbay.craigslist.org/fuo/123.html", "https://sfbay.craigslist.org:8443/fuo/123.html",
      "http://sfbay.craigslist.org:443/fuo/123.html", "javascript:alert(1)", "ftp://sfbay.craigslist.org/fuo/123.html",
      "//sfbay.craigslist.org/fuo/123.html", "https://sfbay.craigslist.org/search/fuo", "https://sfbay.craigslist.org/fuo/",
      "https://sfbay.craigslist.org/fuo/not-a-number.html", "https://sfbay.craigslist.org/fuo/%31%32%33.html",
      "https://sfbay.craigslist.org/fuo/../123.html", "https://sfbay.craigslist.org/fuo/123.html/extra",
      "https://sfbay.craigslist.org/fuo/12 3.html", nil
    ]
    urls.each do |url|
      result = normalize([ item(link: url, image: item["link"], original: item["link"]) ])
      assert_empty result.listings, url.inspect
      assert_equal 1, result.counts[:rejected_url]
    end
  end

  test "requires bounded title and HTTP thumbnail without credentials" do
    [ item(title: " "), item(title: "x" * 301), item(thumbnail: nil), item(thumbnail: "data:image/png;base64,eA=="), item(thumbnail: "https://secret@images.example/a.jpg"), item(thumbnail: "https://images.example:8443/a.jpg") ].each do |candidate|
      result = normalize([ candidate ])
      assert_empty result.listings
      assert_equal 1, result.counts[:missing_metadata]
    end
  end

  test "rejects credential-bearing thumbnail queries without dropping normal image selectors" do
    %w[api_key access_token client_secret signature X-Amz-Signature X-Goog-Credential Key-Pair-Id].each do |name|
      assert_empty normalize([ item(thumbnail: "https://images.example/a.jpg?#{name}=private") ]).listings
    end
    url = "https://encrypted-tbn0.gstatic.com/images?q=tbn:example&usqp=CAU"
    assert_equal url, normalize([ item(thumbnail: url) ]).listings.first[:thumbnail]
  end

  test "uses the destination link and preserves only documented Lens price" do
    result = normalize([ item(image: "https://newyork.craigslist.org/fuo/987.html", price: { "value" => "$120" }, city: "Imaginary", location: "Imaginary") ])
    listing = result.listings.first
    assert_equal "1234567890", listing[:listing_id]
    assert_equal "$120", listing[:price]
    assert_equal "Craigslist area: SF bay area", listing[:location]
    refute listing.key?(:similarity)
    result = normalize([ item(price: "$200 in title") ], route: "lens_then_images", query: "oak chair")
    refute result.listings.first.key?(:price)
  end

  test "deduplicates IDs after metadata validation and reports every disposition" do
    result = normalize([ item(title: ""), item, item(link: "http://sfbay.craigslist.org/fuo/1234567890.html?x=1"), item(link: "https://other.example/a") ] + (1..7).map { |id| item(id.to_s) })
    assert_equal({ input: 11, rejected_url: 1, missing_metadata: 1, duplicates: 1, eligible: 8, limited: 2, displayed: 6 }, result.counts)
    assert_equal "1234567890", result.listings.first[:listing_id]
  end

  test "Lens preserves provider order; Images ranks unique overlap with stable ties" do
    items = [ item("1", title: "Chair"), item("2", title: "Oak chair"), item("3", title: "Oak oak chair chair"), item("4", title: "Walnut table") ]
    assert_equal %w[1 2 3 4], normalize(items, query: "oak chair").listings.map { |entry| entry[:listing_id] }
    assert_equal %w[2 3 1 4], normalize(items, route: "lens_then_images", query: "oak chairs oak").listings.map { |entry| entry[:listing_id] }
  end

  test "selected host must independently belong to the injected approved catalog" do
    assert_raises(ArgumentError) { ListingNormalizer.new(approved_hostnames: []).call([ item ], location: location, route: "lens_only") }
    assert_raises(ArgumentError) { normalize([ item ], route: "lens_then_images") }
  end
end

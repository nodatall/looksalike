require "test_helper"

class EbayListingNormalizerTest < ActiveSupport::TestCase
  def row(id = "123", **fields)
    { "title" => "Wood dining chair", "link" => "https://www.ebay.com/itm/#{id}",
      "thumbnail" => "https://i.ebayimg.com/images/chair.jpg", "location" => "Located in United States" }.merge(fields.stringify_keys)
  end

  def normalize(rows)
    EbayListingNormalizer.call(response: { "organic_results" => rows }, category: "chair")
  end

  test "validates exact item and image destinations before trusting provider rows" do
    bad = [ "http://www.ebay.com/itm/123", "https://www.ebay.com.evil.test/itm/123", "https://user:pass@www.ebay.com/itm/123",
      "https://www.ebay.com:444/itm/123", "https://www.ebay.com/sch/123", "https://www.ebay.com/itm/123/extra",
      "https://www.ebay.com/itm/123?api_key=secret", "https://www.ebay.com/itm/123\\evil" ]
    bad.each { |url| assert_empty normalize([ row(link: url) ]).listings, url }
    [ "https://i.ebayimg.com.evil.test/chair.jpg", "http://i.ebayimg.com/chair.jpg", "https://user@i.ebayimg.com/chair.jpg",
      "https://i.ebayimg.com:444/chair.jpg", "https://i.ebayimg.com/chair.jpg?X-Amz-Signature=secret",
      "https://i.ebayimg.com/chair.jpg?size=large", "https://i.ebayimg.com/chair.svg", "https://i.ebayimg.com/chair.jpg#photo",
      "https://i.ebayimg.com/a/../chair.jpg", "https://i.ebayimg.com/a/./chair.jpg", "https://i.ebayimg.com/%2e/chair.jpg",
      "https://i.ebayimg.com/a%2Fb/chair.jpg", "https://i.ebayimg.com/a%5Cb/chair.jpg", "https://i.ebayimg.com/a%00/chair.jpg" ].each do |url|
      assert_empty normalize([ row(thumbnail: url) ]).listings, url
    end
    [ "https://i.ebayimg.com/images/chair.jpg", "https://i.ebayimg.com/images/chair.JPEG",
      "https://i.ebayimg.com/images/chair.png", "https://i.ebayimg.com/images/chair.webp" ].each do |url|
      assert_equal url, normalize([ row(thumbnail: url) ]).listings.first["thumbnail"]
    end
    valid = normalize([ row(link: "https://ebay.com/itm/Wood-Chair/123?hash=abc#photo") ]).listings.first
    assert_equal "https://www.ebay.com/itm/123", valid["url"]
  end

  test "filters country identity and complete furniture equally for promoted results in provider order" do
    rows = [ row("1", sponsored: true), row("1", link: "https://ebay.com/itm/Other-Title/1?hash=abc"),
      row("2", location: "Located in Canada"), row("3", location: nil), row("4", title: "Loose chair spindles", sponsored: true),
      row("5", thumbnail: nil), row("6", title: nil) ] + (7..14).map { |id| row(id.to_s) }
    result = normalize(rows)
    assert_equal %w[1 7 8 9 10 11 12 13 14], result.listings.map { |item| item["id"] }
    assert_equal true, result.listings.first["sponsored"]
    assert_equal 2, result.counts["not_explicit_us"]
    assert_equal 1, result.counts["duplicate"]
    assert_equal 2, result.counts["missing_metadata"]
    assert_equal 1, result.counts["title_rejected"]
    assert_equal 9, result.counts["accepted"]
    assert_equal 6, result.counts["displayed"]
  end

  test "retains the complete bounded result set for browser pagination" do
    rows = (1..100).map { |id| row(id.to_s) }
    result = normalize(rows)
    assert_equal rows.map { |item| item["link"].split("/").last }, result.listings.map { |item| item["id"] }
    assert_equal 100, result.counts["accepted"]
    assert_equal 6, result.counts["displayed"]
  end

  test "only supplied safe metadata and price ranges survive; empty results are valid" do
    result = normalize([ row(price: { "raw" => "$100–$200", "from" => { "raw" => "$100" }, "to" => { "raw" => "$200" }, "value" => 100 },
      condition: "Pre-Owned", shipping: "Free delivery", subtitle: "private") ]).listings.first
    assert_equal({ "raw" => "$100–$200", "from" => "$100", "to" => "$200" }, result["price"])
    assert_equal "Pre-Owned", result["condition"]
    assert_equal "Free delivery", result["shipping"]
    refute result.key?("subtitle")
    missing = normalize([ row(price: 100) ]).listings.first
    assert_nil missing["price"]
    assert_nil missing["shipping"]
    [ "https://example.test/photo", "HTTPS://example.test/photo", "http:example", "HtTpS:", "data:image/jpeg;base64,private", "DATA:private" ].each do |reference|
      listing = normalize([ row(title: "Wood dining chair #{reference}", price: { "raw" => "$100 #{reference}" },
        condition: "Used #{reference}", shipping: "Delivery #{reference}") ]).listings.first
      assert_equal "Wood dining chair [URL omitted]", listing["title"]
      assert_equal "$100 [URL omitted]", listing.dig("price", "raw")
      assert_equal "Used [URL omitted]", listing["condition"]
      assert_equal "Delivery [URL omitted]", listing["shipping"]
    end
    [ [ "é", 1 ], [ "🪑", 2 ] ].each do |character, units|
      title = "Wood dining chair " + character * ((300 - "Wood dining chair ".length) / units)
      assert_equal title, normalize([ row(title: title) ]).listings.first["title"]
      assert_empty normalize([ row(title: title + character) ]).listings
      { condition: 100, shipping: 200 }.each do |field, limit|
        boundary = character * (limit / units)
        assert_equal boundary, normalize([ row(**{ field => boundary }) ]).listings.first[field.to_s]
        assert_nil normalize([ row(**{ field => boundary + character }) ]).listings.first[field.to_s]
      end
      price = %w[raw from to].to_h { |field| [ field, character * (80 / units) ] }
      assert_equal price, normalize([ row(price: price) ]).listings.first["price"]
      assert_nil normalize([ row(price: price.transform_values { |value| value + character }) ]).listings.first["price"]
    end
    assert_empty normalize([]).listings
    assert_raises(ArgumentError) { normalize(Array.new(101) { row }) }
  end

  test "preserves shipping quotes in either provider format without inventing missing costs" do
    [ "+$6.35", "+$125.00 shipping", "Free delivery", "Free delivery Import fees due prior to delivery", "Local pickup only" ].each do |quote|
      [ quote, { "raw" => quote, "extracted" => 6.35 } ].each do |shipping|
        assert_equal quote, normalize([ row(shipping: shipping) ]).listings.first["shipping"]
      end
    end
    [ nil, 6.35, [], {}, { "extracted" => 6.35 }, { "raw" => 6.35 }, { "raw" => "" }, { "raw" => "x" * 201 } ].each do |shipping|
      assert_nil normalize([ row(shipping: shipping) ]).listings.first["shipping"]
    end
    listing = normalize([ row(shipping: { "raw" => "+$6.35 https://example.test/private" }) ]).listings.first
    assert_equal "+$6.35 [URL omitted]", listing["shipping"]
    result = EbayListingNormalizer.call(response: { "organic_results" => [ row(shipping: { "raw" => "+$6.35 private" }) ] },
      category: "chair", redact: ->(value) { value.gsub("private", "[redacted]") })
    assert_equal "+$6.35 [redacted]", result.listings.first["shipping"]
  end
end

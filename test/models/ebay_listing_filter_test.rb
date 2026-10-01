require "test_helper"

class EbayListingFilterTest < ActiveSupport::TestCase
  def row(title, sponsored: false)
    { "title" => title, "url" => "https://www.ebay.com/itm/123", "sponsored" => sponsored }
  end

  test "filters recorded wrong items and parts before choosing results in provider order" do
    titles = [
      "Vintage Baker Furniture Faux Bamboo Cane Console Server Sideboard Sofa Table",
      "Hand-Knotted Floral 100% Silk Vegetable Dye Vintage Hereke Turkish Rug 3x5 Ft",
      "Vintage Hand-Knotted Semi-Antique Keshan Area Rug | 9'7 x 12'9 | 100% Wool",
      "Antique carved wood settee", "Replacement wood legs for sofa", "Tufted Victorian couch"
    ]
    rows = titles.map { |title| row(title, sponsored: true) }
    result = EbayListingFilter.call(rows: rows, category: "sofa")
    assert_equal [ rows[3], rows[5] ], result.accepted
    assert_same rows[3], result.accepted.first
    assert_equal [ rows[0], rows[1], rows[2], rows[4] ], result.rejected.map { |entry| entry[:row] }
    assert_equal({ "wrong_category" => 1, "different_item" => 2, "accessory_or_part" => 1, "accepted" => 2 }, result.counts)
    assert_equal EbayListingFilter::VERSION, result.version
    assert_equal titles, rows.map { |entry| entry["title"] }
    assert_equal result.accepted.map { |entry| entry["title"] },
      EbayListingFilter.call(rows: titles.map { |title| row(title) }, category: "sofa").accepted.map { |entry| entry["title"] }
  end

  test "complete furniture is distinct from replacement parts covers and miniature furniture" do
    [ "Replacement sofa", "Sofa with wood legs", "Wood couch w/ carved legs", "Sofa bed with storage",
      "Rolled arms velvet settee", "Vintage loveseat", "Modern sectional" ].each do |title|
      assert_equal 1, EbayListingFilter.call(rows: [ row(title) ], category: "sofa").accepted.length, title
    end
    [ "Replacement chair legs", "Wood bun feet for chair", "Sofa covers", "Slipcover compatible with sofa",
      "Dollhouse carved sofa", "Miniature couch", "Console/sofa table", "Sofa chair table set", "Sofa side table", "Sofa end table" ].each do |title|
      category = title.include?("chair") && !title.include?("Sofa") ? "chair" : "sofa"
      assert_empty EbayListingFilter.call(rows: [ row(title) ], category: category).accepted, title
    end
  end

  test "category families accept real subtypes but preserve furniture identity" do
    [ [ "chair", "Oak dining chair" ], [ "chair", "Iris Turned Leg Wood Dining Chair, Set of 2, Weathered White" ],
      [ "dining chair", "Wood armchair" ], [ "table", "Wood coffee table" ],
      [ "nightstand", "Bedside table" ], [ "bookcase", "Wood shelves" ], [ "dresser", "Chest of drawers" ] ].each do |category, title|
      assert_equal 1, EbayListingFilter.call(rows: [ row(title) ], category: category).accepted.length, title
    end
    [ [ "table", "Wood nightstand" ], [ "coffee table", "Dining table" ], [ "dining chair", "Office chair" ],
      [ "dresser", "Wood cabinet" ], [ "sofa", "Console table" ] ].each do |category, title|
      assert_empty EbayListingFilter.call(rows: [ row(title) ], category: category).accepted, title
    end
  end

  test "replacement cushions are accessories but upholstery and included cushions are not" do
    [ "Replacement seat cushions for sofa", "Sofa replacement cushion foam", "Replacement foam for couch" ].each do |title|
      result = EbayListingFilter.call(rows: [ row(title) ], category: "sofa")
      assert_empty result.accepted, title
      assert_equal "accessory_or_part", result.rejected.first[:reason]
    end
    [ "Sofa with cushions", "Sofa with replacement cushions", "Foam upholstered sofa", "Sofa upholstered in foam" ].each do |title|
      assert_equal 1, EbayListingFilter.call(rows: [ row(title) ], category: "sofa").accepted.length, title
    end
  end

  test "loose chair spindles are parts but complete spindle chairs remain eligible" do
    [ "Oak Wood Turned Spindle For Chairs",
      "Antique 1890s Victorian Turned Wood Chair Spindles – Set of 6 – Original",
      "Unfinished Oak Spindle for Chair | Unstained Wood Spindle, Unpainted Wooden Spin",
      "Vintage Worn Set Of Three Wooden Chair Spindles For Crafts Decor 13”" ].each do |title|
      result = EbayListingFilter.call(rows: [ row(title) ], category: "chair")
      assert_empty result.accepted, title
      assert_equal "accessory_or_part", result.rejected.first[:reason]
    end
    [ "Antique 1874 Chair 19th Century Wooden Turned C Turned Spindle Bow Back",
      "Spindle Slatback Dining Side Chair", "Spindle back chair", "Chair with replacement spindles" ].each do |title|
      assert_equal 1, EbayListingFilter.call(rows: [ row(title) ], category: "chair").accepted.length, title
    end
  end

  test "requires a recognized category and explains unrecognized titles" do
    [ nil, "vintage sofa", "unknown" ].each do |category|
      assert_raises(ArgumentError) { EbayListingFilter.call(rows: [], category: category) }
    end
    result = EbayListingFilter.call(rows: [ row(nil), row("Beautiful furniture") ], category: "sofa")
    assert_empty result.accepted
    assert_equal %w[missing_title missing_furniture_type], result.rejected.map { |entry| entry[:reason] }
  end
end

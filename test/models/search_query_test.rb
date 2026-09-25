require "test_helper"

class SearchQueryTest < ActiveSupport::TestCase
  test "titles vote once per normalized type and a noisy first title cannot win" do
    cases = [
      [ [ "Cabinet company", "Modern chairs", "Painted chair" ], "chair", "chair" ],
      [ [ "Cabinet cabinet cabinet", "Chairs", "CHAIR" ], "chair", "chair" ],
      [ [ "Green velvet couches", "Green velvet settees" ], "green velvet sofa", "sofa" ],
      [ [ "CAFÉ-style armchairs", "armchair" ], "armchair", "armchair" ],
      [ [ "bookshelves", "bookcase" ], "bookcase", "bookcase" ],
      [ [ "benchs", "wood benches", "wood bench" ], "wood bench", "bench" ],
      [ [ "shelfs", "oak shelves", "oak shelf" ], "oak shelf", "shelf" ]
    ]
    cases.each do |titles, phrase, category|
      result = query(titles, related: "red bed")
      assert_equal phrase, result.phrase
      assert_equal category, result.category
      assert_equal "visual_match_titles", result.source
    end
  end

  test "traits need two supporting titles and cannot come from unrelated matches" do
    cases = [
      [ [ "Walnut walnut red chair", "Red oak chair", "Oak walnut table" ], "red chair" ],
      [ [ "Chair walnut walnut walnut", "Chair" ], "chair" ],
      [ [ "White wood wallpaper", "White storage coffee table", "Modern farmhouse coffee table", "Farmhouse coffee table" ], "farmhouse coffee table" ],
      [ [ "red blue wooden oak antique chairs", "red blue wooden oak antique chair" ], "red wood chair" ]
    ]
    cases.each { |titles, expected| assert_equal expected, query(titles).phrase }
  end

  test "empty singleton and tied title votes stay weak even with a related query" do
    cases = [ [], [ "chair" ], [ "chair chair chair" ], [ "wheelchairs", "wheelchair" ],
      [ "chair", "chair", "table", "table" ], [ "table chair oak", "chair table oak" ],
      [ "ornate red" ] * 8 + [ "chair", "chair" ] ]
    cases.each do |titles|
      result = query(titles, related: "red chair")
      assert_nil result.phrase
      assert_nil result.category
      assert_equal "weak_recognition", result.source
    end
    [ nil, [], {}, { "visual_matches" => "chair" }, { "visual_matches" => [ nil, 1, {} ] } ].each do |payload|
      assert_nil SearchQuery.call(payload).phrase
    end
  end

  test "compound types consume generic tokens and preserve subtype disagreement" do
    cases = [
      [ [ "Coffee tables", "coffee table", "Dining table" ], "coffee table" ],
      [ [ "Dining chairs", "dining chair", "Chair" ], "dining chair" ],
      [ [ "office chair", "office chair" ], "office chair" ],
      [ [ "coffee table", "coffee table", "dining table", "dining table" ], nil ],
      [ [ "coffee table", "table" ], nil ]
    ]
    cases.each do |titles, expected|
      result = query(titles)
      expected ? assert_equal(expected, result.phrase) : assert_nil(result.phrase)
    end
  end

  test "saved phrases simplify without changing ranking tokenization" do
    cases = {
      "sofa green velvet seater" => "green velvet sofa",
      "sofa antique photos download free settees vintage" => "antique sofa",
      "antique settee" => "antique sofa",
      "Grey wooden couches best free photos" => "gray wood sofa",
      "white farmhouse coffee tables" => "white farmhouse coffee table",
      "coffee coffee table" => "coffee table",
      "coffee and table" => "table",
      "coffee 2 table" => "table",
      "coffee-table" => "coffee table",
      "oak dining chairs" => "oak dining chair"
    }
    cases.each { |text, expected| assert_equal expected, SearchQuery.simplify(text) }
    assert_equal %w[settees grey wooden seater], SearchQuery.tokens("settees grey wooden seater")
    assert_equal %w[coffee table dining chair], SearchQuery.tokens("coffee tables dining chairs")
    [ nil, " ", "unknown marketing words", "green velvet wallpaper" ].each do |text|
      assert_nil SearchQuery.simplify(text)
    end
  end

  test "recorded modern sofa titles produce the short query" do
    titles = JSON.parse(file_fixture("modern_sofa_titles.json").read)
    result = query(titles)
    assert_equal "green velvet sofa", result.phrase
    assert_equal "furniture-query-v3", result.version
  end

  private
    def query(titles, related: nil)
      SearchQuery.call("related_content" => [ { "query" => related } ],
        "visual_matches" => titles.map { |title| { "title" => title } })
    end
end

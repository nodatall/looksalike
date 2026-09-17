require "test_helper"

class SearchQueryTest < ActiveSupport::TestCase
  test "first qualifying related query wins and categories are whole tokens" do
    cases = [
      [ [ "wheelchairs", "Red CHAIRS for sale", "blue sofa" ], "red chair", "chair" ],
      [ [ "", "Couches, chairs and tables", "antique desk" ], "sofa", "sofa" ],
      [ [ "CAFÉ-style armchairs", "chair" ], "cafe style armchair", "armchair" ],
      [ [ "bookshelves with shelves" ], "bookcase", "bookcase" ],
      [ [ "benchs", "wood benches" ], "wood bench", "bench" ],
      [ [ "shelfs", "oak shelves" ], "oak shelf", "shelf" ]
    ]
    cases.each do |queries, phrase, category|
      result = SearchQuery.call("related_content" => queries.map { |query| { "query" => query } }, "visual_matches" => [ { "title" => "other bed" } ])
      assert_equal phrase, result.phrase
      assert_equal category, result.category
      assert_equal "related_content", result.source
    end
  end

  test "fallback counts a word once per title and keeps first-seen tie order" do
    result = SearchQuery.call("visual_matches" => [
      { "title" => "Walnut walnut red chairs" },
      { "title" => "Red oak chair" },
      { "title" => "Oak walnut tables" }
    ])
    assert_equal "chair walnut red oak", result.phrase
    assert_equal "visual_match_titles", result.source
    assert_equal "chair", SearchQuery.call("visual_matches" => [ { "title" => "chair walnut walnut walnut" } ]).phrase
  end

  test "fallback inspects only first eight positions and needs a usable category" do
    [ {}, { "related_content" => [ { "query" => "wheelchair red" } ] }, { "visual_matches" => [ { "title" => "ornate red" } ] * 8 + [ { "title" => "chair" } ] } ].each do |payload|
      result = SearchQuery.call(payload)
      assert_nil result.phrase
      assert_equal "weak_recognition", result.source
    end
  end

  test "caps at eight unique words and retains a late category" do
    result = SearchQuery.call("related_content" => [ { "query" => "one two three four five six seven eight nine red wood chairs chairs" } ])
    assert_equal "one two three four five six seven chair", result.phrase
    assert_equal 8, result.phrase.split.length
  end

  test "fallback does not combine competing categories" do
    result = SearchQuery.call("visual_matches" => [ { "title" => "table chair oak" }, { "title" => "chair table oak" } ])
    assert_equal "table oak", result.phrase
  end
end

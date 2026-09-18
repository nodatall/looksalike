require "test_helper"

class SearchQueryTest < ActiveSupport::TestCase
  test "first qualifying related query wins and categories are whole tokens" do
    cases = [
      [ [ "wheelchairs", "Red CHAIRS for sale", "blue sofa" ], "red chair", "chair" ],
      [ [ "", "Couches, chairs and tables", "antique desk" ], "sofa", "sofa" ],
      [ [ "CAFÉ-style armchairs", "chair" ], "armchair", "armchair" ],
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
    assert_equal "red walnut chair", result.phrase
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

  test "keeps at most two familiar noncontradictory traits and category last" do
    result = SearchQuery.call("related_content" => [ { "query" => "one two three four five six red blue wooden oak antique chairs chairs" } ])
    assert_equal "red wood chair", result.phrase
    assert_equal 3, result.phrase.split.length
  end

  test "fallback does not combine competing categories" do
    result = SearchQuery.call("visual_matches" => [ { "title" => "table chair oak" }, { "title" => "chair table oak" } ])
    assert_equal "oak table", result.phrase
  end
  test "saved phrases simplify without changing ranking tokenization" do
    assert_equal "green velvet sofa", SearchQuery.simplify("sofa green velvet seater")
    assert_equal "antique sofa", SearchQuery.simplify("sofa antique photos download free settees vintage")
    assert_equal "antique sofa", SearchQuery.simplify("antique settee")
    assert_equal "gray wood sofa", SearchQuery.simplify("Grey wooden couches best free photos")
    assert_equal %w[settees grey wooden seater], SearchQuery.tokens("settees grey wooden seater")
    [ nil, " ", "unknown marketing words", "green velvet wallpaper" ].each do |text|
      assert_nil SearchQuery.simplify(text)
      assert_equal "weak_recognition", SearchQuery.call("related_content" => [ { "query" => text } ]).source
    end
  end

  test "recorded modern sofa titles produce the short query" do
    titles = JSON.parse(file_fixture("modern_sofa_titles.json").read)
    result = SearchQuery.call("visual_matches" => titles.map { |title| { "title" => title } })
    assert_equal "green velvet sofa", result.phrase
    assert_equal "furniture-query-v2", result.version
  end
end

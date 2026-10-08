require "test_helper"

class PhotoQueryTest < ActiveSupport::TestCase
  def answer(category: "sofa", traits: [ "carved wood" ], status: "recognized")
    { "status" => status, "category" => category, "traits" => traits }
  end

  test "fallback includes missing phrases and bare single or compound categories" do
    [ [ nil, nil ], [ "sofa", "sofa" ], [ "coffee table", "coffee table" ] ].each do |phrase, category|
      assert PhotoQuery.fallback?(SearchQuery::Result.new(phrase: phrase, category: category, source: "test", version: "test"))
    end
    refute PhotoQuery.fallback?(SearchQuery.call({ "visual_matches" => [ { "title" => "purple sofa" }, { "title" => "purple sofa" } ] }))
  end

  test "style alone triggers vision while concrete Lens colors and materials do not" do
    SearchQuery::TRAITS[:style].each do |style|
      lens = SearchQuery.call({ "visual_matches" => Array.new(2) { { "title" => "#{style} sofa" } } })
      assert PhotoQuery.fallback?(lens), style
      assert_equal "no_concrete_trait", PhotoQuery.fallback_reason(lens)
    end
    [ "purple sofa", "wood vintage sofa", "velvet sofa", "grey modern chair", "wooden coffee table" ].each do |title|
      lens = SearchQuery.call({ "visual_matches" => Array.new(2) { { "title" => title } } })
      refute PhotoQuery.fallback?(lens), title
      assert_nil PhotoQuery.fallback_reason(lens)
    end
  end

  test "accepts locally checked traits outside historical Lens vocabulary" do
    result = PhotoQuery.call(answer(category: "dining chair", traits: [ "curved back", "wood" ]))
    assert_equal "recognized", result.status
    assert_equal "curved back wood dining chair", result.phrase
    assert_equal "dining chair", result.category
    %w[wooden grey].each { |trait| assert_equal "recognized", PhotoQuery.call(answer(traits: [ trait ])).status }
    PhotoQuery::CATEGORIES.each { |category| assert_equal "recognized", PhotoQuery.call(answer(category: category)).status }
  end

  test "invalid schema and unsafe or redundant traits never produce queries" do
    bad_answers = [ nil, [], {}, answer.merge("extra" => "ignored"), answer.merge(status: "recognized"),
      answer(category: "unknown"), answer(category: nil), answer(status: "invented"), answer(traits: []),
      answer(traits: [ "wood", "curved", "blue" ]), answer(traits: "wood"), answer(traits: [ nil ]),
      answer(traits: [ "wood", "wood" ]), answer(traits: [ "wood", "carved wood" ]) ]
    [ "Sculpted", " blue", "blue ", "blue  wood", "blue-wood", "wood|sofa", "wood:sofa", "http://evil.test",
      "https evil test", "3 legged", "blue\nwood", "site ebay", "wood or blue", "a b c d", "écru", "a" * 31,
      "sofa", "couch", "coffee table", "chair table", "\xFF".b ].each do |trait|
      bad_answers << answer(traits: [ trait ])
    end
    bad_answers.each do |input|
      result = PhotoQuery.call(input)
      assert_equal "invalid_answer", result.status, input.inspect
      assert_nil result.phrase
    end
  end

  test "unclear and not furniture are explicit sanitized outcomes" do
    %w[unclear not_furniture].each do |status|
      result = PhotoQuery.call(answer(status: status, category: nil, traits: []))
      assert_equal status, result.status
      assert_nil result.phrase
      assert_equal "invalid_answer", PhotoQuery.call(answer(status: status)).status
    end
  end
end

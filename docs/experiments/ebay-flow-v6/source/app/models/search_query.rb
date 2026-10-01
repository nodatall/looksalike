# frozen_string_literal: true

class SearchQuery
  VERSION = "furniture-query-v3".freeze
  CATEGORIES = %w[sofa loveseat chair armchair recliner chaise sectional table desk dresser cabinet bookcase shelf bed nightstand bench stool ottoman].freeze
  ALIASES = (CATEGORIES - %w[bench shelf]).to_h { |word| [ "#{word}s", word ] }.merge(
    "couch" => "sofa", "couches" => "sofa", "shelves" => "shelf", "benches" => "bench",
    "bookshelf" => "bookcase", "bookshelves" => "bookcase"
  ).freeze
  STOPWORDS = %w[a an and are as at be by for from in is it of on or that the this to with your you
    buy sale sell selling used new furniture craigslist item items near set pair piece pieces s].freeze
  MAX_TRAITS = 2
  TRAITS = {
    color: %w[red orange yellow green blue purple pink brown black white gray beige tan cream],
    material: %w[wood oak walnut teak pine maple bamboo rattan wicker leather velvet linen fabric metal steel brass glass marble plastic acrylic],
    style: %w[antique vintage modern contemporary traditional victorian rustic farmhouse industrial minimalist scandinavian midcentury ornate]
  }.transform_values(&:freeze).freeze
  QUERY_ALIASES = { "settee" => "sofa", "settees" => "sofa", "grey" => "gray", "wooden" => "wood" }.freeze
  COMPOUND_TYPES = [ "coffee table", "dining table", "side table", "end table", "console table", "bedside table",
    "dining chair", "office chair", "rocking chair", "bar stool" ].freeze
  Result = Data.define(:phrase, :category, :source, :version)

  def self.tokens(text)
    return [] unless text.is_a?(String) && text.valid_encoding?
    text.unicode_normalize(:nfkd).downcase.gsub(/\p{Mn}/, "").scan(/[a-z0-9]+/)
      .map { |word| ALIASES.fetch(word, word) }
      .reject { |word| word.length < 2 || word.match?(/\A[0-9]+\z/) || STOPWORDS.include?(word) }
  rescue Encoding::CompatibilityError, ArgumentError
    []
  end

  # Query-only normalization: ranking continues to use the unchanged tokens method.
  def self.query_tokens(text)
    return [] unless text.is_a?(String) && text.valid_encoding?
    # Keep intervening words and numbers so only adjacent words form compounds.
    text.unicode_normalize(:nfkd).downcase.gsub(/\p{Mn}/, "").scan(/[a-z0-9]+/)
      .map { |word| ALIASES.fetch(word, word) }
      .map { |word| QUERY_ALIASES.fetch(word, word) }
  rescue Encoding::CompatibilityError, ArgumentError
    []
  end

  def self.simplify(text)
    words = query_tokens(text)
    category = recognized_types(words).first
    phrase(category, words)
  end

  def self.recognized_types(words)
    types = []
    index = 0
    while index < words.length
      compound = words[index, 2].join(" ")
      if COMPOUND_TYPES.include?(compound)
        types << compound
        index += 2
      else
        types << words[index] if CATEGORIES.include?(words[index])
        index += 1
      end
    end
    types.uniq
  end
  private_class_method :recognized_types

  def self.phrase(category, words)
    return unless category
    selected = {}
    words.each do |word|
      group = TRAITS.find { |_, vocabulary| vocabulary.include?(word) }&.first
      selected[group] = word if group && !selected.key?(group) && selected.length < MAX_TRAITS
    end
    # Select first-seen traits from distinct groups; display color, material, style.
    (TRAITS.keys.filter_map { |group| selected[group] } + [ category ]).join(" ")
  end
  private_class_method :phrase

  def self.call(response)
    response = {} unless response.is_a?(Hash)
    matches = response["visual_matches"]
    titles = (matches.is_a?(Array) ? matches : []).first(8).map { |entry| query_tokens(entry.is_a?(Hash) ? entry["title"] : nil) }
    types = titles.map { |words| recognized_types(words) }
    votes = types.flatten.tally
    highest = votes.values.max.to_i
    winners = votes.keys.select { |type| votes[type] == highest }
    unless highest >= 2 && winners.one?
      return Result.new(phrase: nil, category: nil, source: "weak_recognition", version: VERSION)
    end
    category = winners.first
    supporting_titles = titles.each_with_index.filter_map { |words, index| words.uniq if types[index].include?(category) }
    frequencies = supporting_titles.flatten.tally
    repeated = frequencies.keys.select { |word| frequencies[word] >= 2 }
    Result.new(phrase: phrase(category, repeated), category: category, source: "visual_match_titles", version: VERSION)
  end
end

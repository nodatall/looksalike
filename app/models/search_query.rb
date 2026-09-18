# frozen_string_literal: true

class SearchQuery
  VERSION = "furniture-query-v2".freeze
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
    tokens(text).map { |word| QUERY_ALIASES.fetch(word, word) }.uniq
  end

  def self.simplify(text)
    words = query_tokens(text)
    category = words.find { |word| CATEGORIES.include?(word) }
    phrase(category, words)
  end

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
    related = response["related_content"]
    (related.is_a?(Array) ? related : []).each do |entry|
      words = query_tokens(entry.is_a?(Hash) ? entry["query"] : nil)
      category = words.find { |word| CATEGORIES.include?(word) }
      next unless category
      return Result.new(phrase: phrase(category, words), category: category, source: "related_content", version: VERSION)
    end

    matches = response["visual_matches"]
    titles = (matches.is_a?(Array) ? matches : []).first(8).map { |entry| query_tokens(entry.is_a?(Hash) ? entry["title"] : nil) }
    category = titles.flatten.find { |word| CATEGORIES.include?(word) }
    return Result.new(phrase: nil, category: nil, source: "weak_recognition", version: VERSION) unless category
    frequencies = titles.flatten.tally
    repeated = frequencies.keys.select { |word| frequencies[word] >= 2 }
    Result.new(phrase: phrase(category, repeated), category: category, source: "visual_match_titles", version: VERSION)
  end
end

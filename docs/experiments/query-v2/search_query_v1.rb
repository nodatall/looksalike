# frozen_string_literal: true

class SearchQuery
  VERSION = "furniture-query-v1".freeze
  CATEGORIES = %w[sofa loveseat chair armchair recliner chaise sectional table desk dresser cabinet bookcase shelf bed nightstand bench stool ottoman].freeze
  ALIASES = (CATEGORIES - %w[bench shelf]).to_h { |word| [ "#{word}s", word ] }.merge(
    "couch" => "sofa", "couches" => "sofa", "shelves" => "shelf", "benches" => "bench",
    "bookshelf" => "bookcase", "bookshelves" => "bookcase"
  ).freeze
  STOPWORDS = %w[a an and are as at be by for from in is it of on or that the this to with your you
    buy sale sell selling used new furniture craigslist item items near set pair piece pieces s].freeze
  MAX_WORDS = 8
  Result = Data.define(:phrase, :category, :source, :version)

  def self.tokens(text)
    return [] unless text.is_a?(String) && text.valid_encoding?
    text.unicode_normalize(:nfkd).downcase.gsub(/\p{Mn}/, "").scan(/[a-z0-9]+/)
      .map { |word| ALIASES.fetch(word, word) }
      .reject { |word| word.length < 2 || word.match?(/\A[0-9]+\z/) || STOPWORDS.include?(word) }
  rescue Encoding::CompatibilityError, ArgumentError
    []
  end

  def self.call(response)
    response = {} unless response.is_a?(Hash)
    related = response["related_content"]
    (related.is_a?(Array) ? related : []).each do |entry|
      words = tokens(entry.is_a?(Hash) ? entry["query"] : nil)
      category = words.find { |word| CATEGORIES.include?(word) }
      next unless category
      words = words.reject { |word| CATEGORIES.include?(word) && word != category }.uniq
      chosen = words.first(MAX_WORDS)
      chosen = words.first(MAX_WORDS - 1) + [ category ] unless chosen.include?(category)
      return Result.new(phrase: chosen.join(" "), category: category, source: "related_content", version: VERSION)
    end

    matches = response["visual_matches"]
    titles = (matches.is_a?(Array) ? matches : []).first(8).map { |entry| tokens(entry.is_a?(Hash) ? entry["title"] : nil).uniq }
    category = titles.flatten.find { |word| CATEGORIES.include?(word) }
    return Result.new(phrase: nil, category: nil, source: "weak_recognition", version: VERSION) unless category
    frequencies = titles.flatten.tally
    descriptive = frequencies.keys.select { |word| frequencies[word] >= 2 && !CATEGORIES.include?(word) }
    Result.new(phrase: ([ category ] + descriptive).first(MAX_WORDS).join(" "), category: category, source: "visual_match_titles", version: VERSION)
  end
end

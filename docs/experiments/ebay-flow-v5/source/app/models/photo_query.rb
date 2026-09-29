# frozen_string_literal: true

# Pure policy: neither photo bytes nor provider IO belong here.
class PhotoQuery
  TRIGGER_VERSION = "photo-fallback-v2"
  VERSION = "photo-phrase-v1"
  CATEGORIES = (SearchQuery::CATEGORIES + SearchQuery::COMPOUND_TYPES).freeze
  OPERATORS = %w[and or not site inurl intitle filetype allintext http https www].freeze
  CATEGORY_WORDS = (CATEGORIES.flat_map(&:split) + SearchQuery::ALIASES.keys + SearchQuery::QUERY_ALIASES.select { |_, value| CATEGORIES.include?(value) }.keys).uniq.freeze
  Result = Data.define(:status, :phrase, :category, :traits)

  def self.fallback?(lens_result)
    !fallback_reason(lens_result).nil?
  end

  def self.fallback_reason(lens_result)
    return "missing_phrase" if lens_result.phrase.nil?
    return "bare_category" if lens_result.phrase == lens_result.category
    concrete_traits = SearchQuery::TRAITS.values_at(:color, :material).flatten
    return "no_concrete_trait" if (SearchQuery.query_tokens(lens_result.phrase) & concrete_traits).empty?
    nil
  end

  def self.call(answer)
    invalid = Result.new(status: "invalid_answer", phrase: nil, category: nil, traits: [])
    return invalid unless answer.is_a?(Hash) && answer.length == 3 && %w[category status traits].all? { |key| answer.key?(key) }
    status, category, traits = answer.values_at("status", "category", "traits")
    if %w[unclear not_furniture].include?(status)
      return invalid unless category.nil? && traits == []
      return Result.new(status: status, phrase: nil, category: nil, traits: [])
    end
    return invalid unless status == "recognized" && CATEGORIES.include?(category)
    return invalid unless traits.is_a?(Array) && (1..2).cover?(traits.length) && traits.uniq.length == traits.length
    return invalid unless traits.all? do |trait|
      trait.is_a?(String) && trait.valid_encoding? && trait.ascii_only? && trait.bytesize <= 30 &&
        trait.match?(/\A[a-z]+(?: [a-z]+){0,2}\z/) &&
        (trait.split & OPERATORS).empty? && !(trait.split - CATEGORY_WORDS).empty?
    end
    # Repeating a trait inside another adds no independent visual detail.
    return invalid if traits.length == 2 && traits.any? { |trait| (trait.split - (traits - [ trait ]).first.split).empty? }
    phrase = (traits + [ category ]).join(" ")
    return invalid if phrase.length > 90
    Result.new(status: status, phrase: phrase, category: category, traits: traits.dup.freeze)
  end
end

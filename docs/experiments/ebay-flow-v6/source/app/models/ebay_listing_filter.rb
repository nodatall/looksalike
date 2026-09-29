# frozen_string_literal: true

# Title eligibility only; normalization, country checks and ranking belong to callers.
class EbayListingFilter
  VERSION = "ebay-title-filter-v2"
  Result = Data.define(:accepted, :rejected, :counts, :version)
  SOFAS = %w[sofa loveseat sectional chaise].freeze
  CHAIRS = [ "chair", "armchair", "recliner", "dining chair", "office chair", "rocking chair" ].freeze
  TABLES = [ "table", "coffee table", "dining table", "side table", "end table", "console table", "bedside table" ].freeze
  PARTS = %w[leg legs feet foot cover covers slipcover slipcovers protector protectors pillow pillows
    riser risers knob knobs handle handles hinge hinges caster casters castor castors slat slats hardware].freeze
  OTHER_ITEMS = %w[rug rugs carpet carpets runner tapestry curtain curtains poster print photograph miniature dollhouse dollhouses].freeze
  TITLE_ALIASES = { "settee" => "sofa", "chesterfield" => "sofa", "credenza" => "cabinet", "sideboard" => "cabinet", "buffet" => "cabinet" }.freeze

  def self.call(rows:, category:)
    raise ArgumentError, "Recognized furniture category required" unless PhotoQuery::CATEGORIES.include?(category)
    accepted = []
    rejected = []
    rows.each do |row|
      reason = rejection_reason(row["title"], category)
      reason ? rejected << { row: row, reason: reason } : accepted << row
    end
    counts = rejected.map { |entry| entry[:reason] }.tally.merge("accepted" => accepted.length)
    Result.new(accepted: accepted, rejected: rejected, counts: counts, version: VERSION)
  end

  def self.rejection_reason(title, category)
    words = SearchQuery.query_tokens(title).map { |word| TITLE_ALIASES.fetch(word, word) }
    return "missing_title" if words.empty?
    return "miniature" if (words & %w[miniature dollhouse dollhouses]).any? || words.each_cons(2).any? { |pair| pair == %w[doll house] }
    # Features after 'with' describe the complete item, e.g. 'sofa with wood legs'.
    head = words.take_while { |word| !%w[with w].include?(word) }
    parts = head.each_with_index.select do |word, index|
      next false unless PARTS.include?(word)
      # 'Turned leg dining chair' names a chair; 'replacement chair legs' names parts.
      !(word == "leg" && index.positive? && %w[turned tapered].include?(head[index - 1]) && item_types(head.drop(index + 1)).any?)
    end
    replacement_cushion = head.join(" ").match?(/\breplacement (?:seat |back |cushion )?(?:cushions?|foam)\b/)
    loose_spindle = head.join(" ").match?(/\bspindles?\b.*\bfor chair\b|\bchair spindles\b/)
    return "accessory_or_part" if parts.any? || replacement_cushion || loose_spindle || head.each_cons(2).any? { |pair| pair == %w[replacement part] }
    return "different_item" if (head & OTHER_ITEMS).any?
    types = item_types(head)
    return "missing_furniture_type" if types.empty?
    return "wrong_category" unless types.any? { |type| compatible?(type, category) }
    return "mixed_categories" unless types.all? { |type| compatible?(type, category) }
    nil
  end
  private_class_method :rejection_reason

  def self.item_types(words)
    types = []
    index = 0
    while index < words.length
      compound = words[index, 2].join(" ")
      if compound == "sofa bed"
        types << "sofa"
        index += 2
      elsif compound == "sofa table"
        types << "console table"
        index += 2
      elsif compound == "chest of" && words[index + 2] == "drawers"
        types << "dresser"
        index += 3
      elsif SearchQuery::COMPOUND_TYPES.include?(compound)
        types << compound
        index += 2
      else
        types << words[index] if SearchQuery::CATEGORIES.include?(words[index])
        index += 1
      end
    end
    types.uniq
  end
  private_class_method :item_types

  def self.compatible?(type, category)
    return true if type == category
    return true if SOFAS.include?(type) && SOFAS.include?(category)
    return true if category == "chair" && CHAIRS.include?(type)
    return true if CHAIRS.include?(category) && %w[chair armchair].include?(type)
    return true if category == "table" && TABLES.include?(type)
    return true if TABLES.include?(category) && type == "table"
    return true if [ "nightstand", "bedside table" ].include?(type) && [ "nightstand", "bedside table" ].include?(category)
    return true if %w[shelf bookcase].include?(type) && %w[shelf bookcase].include?(category)
    return true if [ "stool", "bar stool" ].include?(type) && [ "stool", "bar stool" ].include?(category)
    false
  end
  private_class_method :compatible?
end

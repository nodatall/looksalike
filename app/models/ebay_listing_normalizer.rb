require "uri"

# Validate item identity and location, then apply the title policy in provider order.
class EbayListingNormalizer
  VERSION = "ebay-listings-v7"
  US_RULE = "explicit-us-v1"
  CREDENTIAL_PARAMETERS = ListingNormalizer::CREDENTIAL_PARAMETERS
  Result = Data.define(:listings, :counts, :version)

  def self.call(response:, category:, redact: ->(value) { value })
    rows = response.fetch("organic_results", [])
    raise ArgumentError, "Invalid eBay results" unless rows.is_a?(Array) && rows.length <= 100
    counts = { "returned" => rows.length, "invalid_url" => 0, "missing_metadata" => 0,
      "not_explicit_us" => 0, "duplicate" => 0 }
    seen = {}
    eligible = rows.filter_map do |row|
      link = item_link(row.is_a?(Hash) ? row["link"] : nil)
      unless link
        counts["invalid_url"] += 1
        next
      end
      id, url = link
      title = text(row["title"], 300, redact)
      thumbnail = image_link(row["thumbnail"])
      unless title && thumbnail
        counts["missing_metadata"] += 1
        next
      end
      unless row["location"] == "Located in United States"
        counts["not_explicit_us"] += 1
        next
      end
      if seen[id]
        counts["duplicate"] += 1
        next
      end
      seen[id] = true
      { "id" => id, "title" => title, "url" => url, "thumbnail" => thumbnail,
        "sponsored" => row["sponsored"] == true, "price" => price(row["price"], redact),
        "condition" => text(row["condition"], 100, redact), "shipping" => shipping(row["shipping"], redact),
        "location" => "Located in United States" }
    end
    filtered = EbayListingFilter.call(rows: eligible, category: category)
    counts.merge!("eligible" => eligible.length, "title_rejected" => filtered.rejected.length,
      "title_rejection_reasons" => filtered.counts.except("accepted"), "accepted" => filtered.accepted.length,
      "displayed" => [ filtered.accepted.length, 6 ].min)
    Result.new(listings: filtered.accepted, counts: counts, version: VERSION)
  end

  def self.safe_uri(value)
    return unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= 2048
    return if value.match?(/[[:space:]\\]/)
    uri = URI.parse(value)
    return unless uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil? && uri.port == 443
    names = URI.decode_www_form(uri.query.to_s).map { |name, _| name.downcase.tr("-", "_") }
    return if names.any? { |name| CREDENTIAL_PARAMETERS.include?(name) || name.start_with?("x_amz_", "x_goog_") }
    uri
  rescue URI::InvalidURIError, ArgumentError
    nil
  end
  private_class_method :safe_uri

  def self.item_link(value)
    uri = safe_uri(value)
    return unless uri && %w[ebay.com www.ebay.com].include?(uri.host.downcase)
    id = uri.path.match(%r{\A/itm/(?:[a-zA-Z0-9_%~-]+/)?([1-9][0-9]{0,19})\z})&.[](1)
    [ id, "https://www.ebay.com/itm/#{id}" ] if id
  end
  private_class_method :item_link

  def self.image_link(value)
    uri = safe_uri(value)
    return unless uri && value.match?(%r{\Ahttps://i\.ebayimg\.com/[a-zA-Z0-9_~./%-]+\.(?:jpg|jpeg|png|webp)\z}i)
    return if value.match?(/%(?:2f|5c|2e|00)/i) || value.include?("/../") || value.include?("/./")
    value
  end
  private_class_method :image_link

  def self.text(value, length, redact)
    return unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= length * 4
    value = redact.call(value).gsub(/(?:https?|data):\S*/i, "[URL omitted]").gsub(/[[:space:]]+/, " ").strip
    units = value.each_codepoint.sum { |point| point > 0xFFFF ? 2 : 1 }
    value if !value.empty? && units <= length && !value.match?(/[[:cntrl:]]/)
  end
  private_class_method :text

  def self.shipping(value, redact)
    supplied = value.is_a?(Hash) ? value["raw"] : value
    text(supplied, 200, redact)
  end
  private_class_method :shipping

  def self.price(value, redact)
    return unless value.is_a?(Hash)
    result = %w[raw from to].filter_map do |key|
      supplied = value[key].is_a?(Hash) ? value[key]["raw"] : value[key]
      safe = text(supplied, 80, redact)
      [ key, safe ] if safe
    end.to_h
    result unless result.empty?
  end
  private_class_method :price
end

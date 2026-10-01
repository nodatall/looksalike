# frozen_string_literal: true

require "uri"

class ListingNormalizer
  VERSION = "craigslist-listings-v1".freeze
  ROUTES = %w[lens_only lens_then_images].freeze
  LISTING_PATH = %r{\A/(?:[a-z]{3}/)?[a-z]{3}/(?:d/[a-z0-9][a-z0-9-]*/)?([0-9]{1,20})\.html\z}
  CREDENTIAL_PARAMETERS = %w[api_key apikey access_token token secret client_secret authorization auth signature sig
    key policy key_pair_id awsaccesskeyid googleaccessid].freeze
  Result = Data.define(:listings, :counts, :version)

  def initialize(approved_hostnames:)
    @approved = approved_hostnames.to_h { |host| [ host, true ] }.freeze
  end

  def call(items, location:, route:, query: nil)
    raise ArgumentError, "Unsupported search route" unless ROUTES.include?(route)
    hostname = location.hostname
    raise ArgumentError, "Unapproved search area" unless @approved[hostname] && hostname.match?(/\A[a-z0-9-]+\.craigslist\.org\z/)
    raise ArgumentError, "Images ranking requires a phrase" if route == "lens_then_images" && SearchQuery.tokens(query).empty?
    items = [] unless items.is_a?(Array)
    counts = { input: items.length, rejected_url: 0, missing_metadata: 0, duplicates: 0, eligible: 0, limited: 0, displayed: 0 }
    seen = {}
    eligible = []
    query_tokens = SearchQuery.tokens(query).uniq
    items.each_with_index do |item, index|
      link = listing_link(item.is_a?(Hash) ? item["link"] : nil, hostname)
      unless link
        counts[:rejected_url] += 1
        next
      end
      title = text(item["title"], 300)
      thumbnail = image_link(item["thumbnail"])
      unless title && thumbnail
        counts[:missing_metadata] += 1
        next
      end
      id, url = link
      if seen[id]
        counts[:duplicates] += 1
        next
      end
      seen[id] = true
      listing = { listing_id: id, title: title, url: url, thumbnail: thumbnail,
        location: "Craigslist area: #{location.area_name}", location_source: "selected_area" }
      if route == "lens_only" && item["price"].is_a?(Hash) && (price = text(item["price"]["value"], 80))
        listing[:price] = price
      end
      overlap = (query_tokens & SearchQuery.tokens(title).uniq).length
      eligible << [ listing, overlap, index ]
    end
    eligible.sort_by! { |_, overlap, index| [ -overlap, index ] } if route == "lens_then_images"
    counts[:eligible] = eligible.length
    listings = eligible.first(6).map(&:first)
    counts[:displayed] = listings.length
    counts[:limited] = eligible.length - listings.length
    Result.new(listings: listings, counts: counts, version: VERSION)
  end

  private
    def safe_uri(value)
      return unless value.is_a?(String) && value.bytesize <= 2048 && value.valid_encoding?
      return if value.match?(/[[:space:]\\]/)
      uri = URI.parse(value)
      return unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme) && uri.host && uri.userinfo.nil?
      return unless uri.port == (uri.scheme == "https" ? 443 : 80)
      uri
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def listing_link(value, hostname)
      uri = safe_uri(value)
      return unless uri && uri.host.downcase == hostname
      match = LISTING_PATH.match(uri.path)
      return unless match
      [ match[1].to_i.to_s, URI::HTTPS.build(host: hostname, path: uri.path).to_s ]
    end

    def image_link(value)
      uri = safe_uri(value)
      return unless uri
      names = URI.decode_www_form(uri.query.to_s).map { |name, _| name.downcase.tr("-", "_") }
      return if names.any? { |name| CREDENTIAL_PARAMETERS.include?(name) || name.start_with?("x_amz_", "x_goog_") }
      # Ordinary image selection parameters (such as Google's q) remain intact.
      uri.fragment = nil
      uri.to_s
    rescue ArgumentError
      nil
    end

    def text(value, max_length)
      return unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= max_length * 4
      value = value.gsub(/[[:space:]]+/, " ").strip
      return if value.empty? || value.length > max_length || value.match?(/[\x00-\x1f\x7f]/)
      value
    rescue ArgumentError
      nil
    end
end

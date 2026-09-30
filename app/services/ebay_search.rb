require "digest"

# One request's synchronous photo-to-eBay flow. Stores own accounting; clients own HTTP.
class EbaySearch
  VERSION = "ebay-us-v1"
  class Disconnected < StandardError; end
  MESSAGES = {
    "disabled" => "Live search is unavailable. Please try again later.",
    "busy" => "Another search is running. Please try again shortly.",
    "quota_exceeded" => "The demo has reached its search allowance. Please try again later.",
    "visitor_limit" => "You have reached the hourly search limit. Please try again later.",
    "vision_limit" => "Photo recognition has reached its allowance. Please try again later.",
    "storage_unavailable" => "Search storage is unavailable. Please try again later.",
    "configuration_error" => "Live search is unavailable. Please try again later.",
    "invalid_photo" => "This photo could not be processed. Choose another photo.",
    "unclear" => "We could not identify this furniture. Choose another furniture photo.",
    "not_furniture" => "We could not find furniture in this photo. Choose a furniture photo.",
    "insufficient_time" => "Photo recognition took too long. Please try again.",
    "deadline" => "The search took too long. Please try again.",
    "invalid_response" => "The search service returned an unreadable response. Please try again later.",
    "provider_unavailable" => "The search service is unavailable. Please try again later."
  }.freeze

  def initialize(client: SerpApi::Client.new, vision_client: Vision::Client.new, store: nil, settings: nil,
    enabled: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, now: -> { Time.now.utc })
    @client, @vision_client, @store, @settings, @enabled, @clock, @now = client, vision_client, store, settings, enabled, clock, now
  end

  def call(photo:, session_id:, ip:, progress: ->(_) { }, deadline: nil)
    @stages, @attempts, @progress = [], { "uploads" => 0, "serpapi" => 0, "vision" => 0 }, progress
    @settings ||= SearchSettings.new
    @store ||= SearchStore.new(settings: @settings, now: @now)
    deadline ||= SearchDeadline.new(seconds: @settings.deadline_seconds, clock: @clock)
    deadline.within do
      validated = PhotoValidator.call(photo, deadline: deadline)
      unless validated.content_type == "image/jpeg" && [ validated.width, validated.height ].max <= 1600
        return result("invalid_photo")
      end
      key = SearchStore.cache_key(Digest::SHA256.hexdigest(validated.bytes))
      if (saved = @store.lookup(key))
        return saved
      end
      return result("disabled") unless @enabled.nil? ? @settings.enabled? : @enabled
      grant = @store.acquire(key: key, session_id: session_id, ip: ip)
      return grant.cached_result if grant.status == "cache"
      return result(grant.status) unless grant.status == "live"
      @token = grant.token

      @image_id = stage("upload", { "provider" => "serpapi", "endpoint" => "/image",
        "parameters" => { "format" => validated.content_type, "bytes" => validated.bytes.bytesize } }) do
        @attempts["uploads"] += 1
        id = @client.upload(photo: validated.bytes, deadline: deadline)
        [ id, { "photo_reference_received" => true } ]
      end
      lens = stage("lens", { "provider" => "serpapi", "endpoint" => "/search.json",
        "parameters" => { "engine" => "google_lens", "type" => "all", "country" => "us", "hl" => "en" } }) do
        @attempts["serpapi"] += 1
        data = @client.lens(image_id: @image_id, type: "all", deadline: deadline)
        matches = data["visual_matches"].is_a?(Array) ? data["visual_matches"] : []
        phrase = SearchQuery.call(data)
        [ data, { "visual_matches" => matches.length, "query" => safe_text(phrase.phrase, 90), "category" => phrase.category,
          "titles" => matches.first(8).filter_map { |row| safe_text(row.is_a?(Hash) ? row["title"] : nil) } } ]
      end
      prepared = EbayQueryPreparation.new(vision_client: @vision_client, clock: @clock).call(
        lens_response: lens, photo: validated, deadline: deadline,
        before_vision_dispatch: ->(_) { reserve_vision })
      record_preparation(prepared)
      unless prepared.status == "ready"
        status = if @vision_storage_failed then "storage_unavailable"
        elsif @vision_denied then "vision_limit"
        else recognition_status(prepared.status)
        end
        return result(status)
      end
      @query, @category = safe_text(prepared.query, 90), prepared.category
      data = stage("ebay", { "provider" => "serpapi", "endpoint" => "/search.json",
        "parameters" => { "engine" => "ebay", "_nkw" => @query, "ebay_domain" => "ebay.com", "_ipg" => "25" } }) do
        @attempts["serpapi"] += 1
        response = @client.ebay(query: prepared.query, deadline: deadline)
        rows = response["organic_results"].is_a?(Array) ? response["organic_results"] : []
        [ response, { "returned" => rows.length, "titles" => rows.first(6).filter_map { |row| safe_text(row.is_a?(Hash) ? row["title"] : nil) } } ]
      end
      normalized = stage("filter", { "provider" => "local", "parameters" => {
        "location_rule" => EbayListingNormalizer::US_RULE, "normalizer_version" => EbayListingNormalizer::VERSION,
        "title_filter_version" => EbayListingFilter::VERSION } }) do
        deadline.remaining
        value = EbayListingNormalizer.call(response: data, category: prepared.category, redact: ->(text) { safe_text(text, 300) })
        deadline.remaining
        [ value, value.counts ]
      end
      completed = result(normalized.listings.empty? ? "empty" : "success", listings: normalized.listings, retrieved_at: @now.call.utc.iso8601(6))
      deadline.remaining
      @store.finish(token: @token, key: key, result: completed)
      @token = nil
      completed
    end
  rescue Disconnected
    nil
  rescue PhotoValidator::Invalid => error
    result("invalid_photo", message: error.message)
  rescue SearchDeadline::Exceeded
    result("deadline")
  rescue SearchSettings::Invalid
    result("configuration_error")
  rescue SearchStore::Error
    result("storage_unavailable")
  rescue SerpApi::Client::Error => error
    result(error.code == :invalid_response ? "invalid_response" : "provider_unavailable")
  rescue ArgumentError, TypeError, KeyError
    result("invalid_response")
  ensure
    @image_id = nil
    begin
      @store&.release(@token)
    rescue SearchStore::Error
      # Unknown spend stays reserved; an expired owner is recovered by the next request.
    end
    input = photo.respond_to?(:tempfile) ? photo.tempfile : photo
    input.close! if input.is_a?(Tempfile)
  end

  private
    def stage(name, request)
      entry = { "stage" => name, "status" => "started", "request" => request }
      @stages << entry
      started = @clock.call
      emit(entry)
      value, summary = yield
      entry.merge!("status" => "complete", "duration_ms" => elapsed(started), "summary" => summary)
      emit(entry)
      value
    rescue Disconnected
      raise
    rescue StandardError
      entry.merge!("status" => "failed", "duration_ms" => elapsed(started))
      emit(entry)
      raise
    end

    def reserve_vision
      unless @store.reserve_vision(@token)
        @vision_denied = true
        return false
      end
      @attempts["vision"] += 1
      @vision_started = @clock.call
      @vision_entry = { "stage" => "vision", "status" => "started", "request" => {
        "provider" => "venice", "endpoint" => "/api/v1/chat/completions", "parameters" => Vision::Client.metadata.except(:reserved_usd).stringify_keys } }
      @stages << @vision_entry
      emit(@vision_entry)
      true
    rescue SearchStore::Error
      @vision_storage_failed = true
      false
    end

    def record_preparation(prepared)
      meta = prepared.metadata.stringify_keys
      safe = meta.slice("lens_version", "trigger_version", "phrase_version", "lens_category", "fallback_reason", "provider", "model", "prompt_version", "schema_version", "duration_ms", "usage")
      safe["traits"] = Array(meta["traits"]).filter_map { |trait| safe_text(trait, 30) } if meta.key?("traits")
      @query_preparation = safe.merge("status" => prepared.status, "source" => prepared.source,
        "query" => safe_text(prepared.query, 90), "category" => prepared.category)
      @query_preparation["lens_query"] = @stages.find { |entry| entry["stage"] == "lens" }.dig("summary", "query")
      if @vision_entry
        @vision_entry.merge!("status" => prepared.status == "ready" ? "complete" : "failed", "duration_ms" => elapsed(@vision_started), "summary" => @query_preparation)
        emit(@vision_entry)
      else
        @stages << { "stage" => "vision", "status" => "skipped", "summary" => { "reason" => meta["fallback_reason"] || "lens_has_concrete_trait" } }
      end
    end

    def recognition_status(status)
      return status if %w[unclear not_furniture insufficient_time invalid_photo invalid_response].include?(status)
      return "deadline" if status == "timeout"
      "provider_unavailable"
    end

    def safe_text(value, limit = 200)
      return unless value.is_a?(String) && value.valid_encoding?
      text = @client.redact(value)
      text = @vision_client.redact(text)
      text = text.gsub(@image_id, "[reference omitted]") if @image_id && !@image_id.empty?
      text = text.gsub(/(?:https?|data):\S*/i, "[URL omitted]").gsub(/[[:cntrl:]]/, " ").strip
      units = 0
      text.each_char.take_while do |character|
        units += character.ord > 0xFFFF ? 2 : 1
        units <= limit
      end.join
    end

    def elapsed(started)
      ((@clock.call - started) * 1000).round
    end

    def emit(entry)
      @progress.call({ "type" => "stage" }.merge(entry.slice("stage", "status", "duration_ms")))
    end

    def result(status, listings: [], retrieved_at: nil, message: nil)
      JSON.parse(JSON.generate({ version: VERSION, status: status, source: "live", marketplace: "ebay.com", scope: "us",
        message: message || MESSAGES[status], retrieved_at: retrieved_at, query: @query, category: @category,
        query_preparation: @query_preparation, listings: listings, stages: @stages || [],
        attempts: (@attempts || {}).dup, original_attempts: (@attempts || {}).dup }))
    end
end

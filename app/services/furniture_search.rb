class FurnitureSearch
  def initialize(client:, accounting:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @client, @accounting, @clock = client, accounting, clock
  end

  def call(photo:, zip:, route:, deadline: SearchDeadline.new, started_at: @clock.call)
    timings = []
    parameters = []
    image_id = nil
    deadline.within do
      raise ArgumentError, "Unsupported route" unless ListingNormalizer::ROUTES.include?(route)
      location = LocationResolver.resolve(zip)
      validated = PhotoValidator.call(photo, deadline: deadline)
      site = "site:#{location.hostname}"
      image_id = stage("upload", timings, deadline) { @client.upload(photo: validated.bytes, deadline: deadline) }
      lens_parameters = { "engine" => "google_lens", "type" => route == "lens_only" ? "visual_matches" : "all", "country" => "us", "hl" => "en" }
      lens_parameters["q"] = site if route == "lens_only"
      parameters << lens_parameters
      lens = stage("lens", timings, deadline) { @client.lens(image_id: image_id, type: lens_parameters.fetch("type"), query: lens_parameters["q"], deadline: deadline) }
      query = route == "lens_then_images" ? SearchQuery.call(lens) : nil
      excerpts = { "visual_match_titles" => excerpt_titles(lens["visual_matches"]), "related_queries" => excerpt_queries(lens["related_content"]) }
      if query && query.phrase.nil?
        result = clean({ "status" => "weak_recognition", "listings" => [], "counts" => {}, "stages" => timings, "parameters" => parameters, "excerpts" => excerpts, "elapsed_ms" => elapsed(started_at) }, image_id)
        deadline.remaining
        return result
      end
      if query && query.phrase.bytesize > 500
        raise SerpApi::Client::Error.new(:invalid_response)
      end
      items = lens["visual_matches"]
      if route == "lens_then_images"
        parameters << { "engine" => "google_images", "q" => "#{query.phrase} #{site}", "location" => location.search_origin, "gl" => "us", "hl" => "en" }
        images = stage("images", timings, deadline) { @client.images(query: "#{query.phrase} #{site}", location: location.search_origin, deadline: deadline) }
        items = images["images_results"]
      end
      normalized = ListingNormalizer.new(approved_hostnames: LocationResolver::CATALOG.fetch("areas").map { |area| area.fetch("hostname") }).call(items, location: location, route: route, query: query&.phrase)
      deadline.remaining
      clean({ "status" => "success", "listings" => normalized.listings, "counts" => normalized.counts, "interpretation" => query&.phrase,
        "stages" => timings, "parameters" => parameters, "excerpts" => excerpts, "elapsed_ms" => elapsed(started_at) }, image_id)
    end
  rescue SearchDeadline::Exceeded, SerpApi::Client::Error, PhotoValidator::Invalid, LocationResolver::InvalidZip, LocationResolver::UnmappedZip, ExperimentLedger::Error => error
    code = error.is_a?(SearchDeadline::Exceeded) ? "deadline" : "failed"
    { "status" => code, "listings" => [], "counts" => {}, "stages" => timings, "parameters" => clean(parameters, image_id), "elapsed_ms" => elapsed(started_at) }
  end

  private
    def stage(name, timings, deadline)
      deadline.remaining
      @accounting.call(name)
      # Reservations are committed before this block. No network inside a transaction.
      deadline.remaining
      began = @clock.call
      status = "failed"
      begin
        value = yield
        deadline.remaining
        status = "success"
        value
      ensure
        timings << { "stage" => name, "elapsed_ms" => elapsed(began), "status" => status }
      end
    end

    def elapsed(start)
      ((@clock.call - start) * 1000).round(3)
    end

    def excerpt_titles(items)
      (items.is_a?(Array) ? items : []).first(8).filter_map { |item| bounded_text(item.is_a?(Hash) ? item["title"] : nil) }
    end

    def excerpt_queries(items)
      (items.is_a?(Array) ? items : []).first(20).filter_map { |item| bounded_text(item.is_a?(Hash) ? item["query"] : nil) }
    end

    def bounded_text(value)
      return unless value.is_a?(String) && value.valid_encoding?
      value.gsub(%r{https?://\S+}i, "[URL omitted]").gsub(/[[:space:]]+/, " ").gsub(/[\x00-\x1f\x7f]/, "").strip[0, 300]
    end

    def clean(value, image_id, field = nil)
      case value
      when Hash then value.to_h { |key, item| [ key.to_s, clean(item, image_id, key.to_s) ] }
      when Array then value.map { |item| clean(item, image_id) }
      when String
        text = @client.redact(value)
        text = text.gsub(image_id, "[redacted]") if image_id && !image_id.empty?
        text = text.gsub(%r{https?://\S+}i, "[URL omitted]") unless %w[url thumbnail].include?(field)
        text.gsub(/\b(?:api_key|access_token|client_secret)=\S+/i, "[credential omitted]")
      else value
      end
    end
end

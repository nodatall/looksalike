require "json"
require "net/http"
require "securerandom"
require "uri"

module SerpApi
  class Client
    ORIGIN = "https://serpapi.com".freeze
    MAX_RESPONSE_BYTES = 2_000_000

    class Error < StandardError
      MESSAGES = {
        unavailable: "The search service is unavailable. Please try again later.",
        invalid_response: "The search service returned an unreadable response.",
        unconfigured: "Live search is not available yet."
      }.freeze
      attr_reader :code

      def initialize(code)
        @code = code
        super(MESSAGES.fetch(code))
      end
    end

    # The injected transport accepts a URI, Net::HTTP request, shared deadline,
    # and response-size cap. It returns [integer HTTP status, body string].
    def initialize(api_key: ENV["SERPAPI_API_KEY"], transport: HttpTransport.new)
      @api_key = api_key.to_s
      @transport = transport
    end

    def inspect
      "#<SerpApi::Client>"
    end

    def upload(photo:, deadline:)
      validated = PhotoValidator.call(photo, deadline: deadline)
      boundary = "looksalike-#{SecureRandom.hex(16)}"
      extension = validated.content_type.split("/").last
      body = +"--#{boundary}\r\nContent-Disposition: form-data; name=\"api_key\"\r\n\r\n#{@api_key}\r\n"
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"photo.#{extension}\"\r\nContent-Type: #{validated.content_type}\r\n\r\n"
      body = body.b << validated.bytes << "\r\n--#{boundary}--\r\n".b
      uri = URI("#{ORIGIN}/image")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = body
      data = perform(uri, request, deadline)
      image_id = data["image_id"]
      raise Error.new(:invalid_response) unless image_id.is_a?(String) && image_id.match?(/\A[[:alnum:]_-]{1,512}\z/)
      deadline.remaining
      image_id
    end

    def lens(image_id:, type:, deadline:, query: nil)
      raise ArgumentError, "Unsupported Lens type" unless %w[all visual_matches].include?(type)
      params = { engine: "google_lens", image_id: image_id, type: type, country: "us", hl: "en" }
      params[:q] = query if query
      search(params, deadline)
    end

    def images(query:, location:, deadline:)
      search({ engine: "google_images", q: query, location: location, gl: "us", hl: "en" }, deadline)
    end

    private
      def search(params, deadline)
        uri = URI("#{ORIGIN}/search.json")
        uri.query = URI.encode_www_form(params.merge(api_key: @api_key))
        data = perform(uri, Net::HTTP::Get.new(uri), deadline)
        raise Error.new(:invalid_response) unless data.dig("search_metadata", "status") == "Success"
        deadline.remaining
        data
      rescue TypeError
        raise Error.new(:invalid_response), cause: nil
      end

      def perform(uri, request, deadline)
        raise Error.new(:unconfigured) if @api_key.empty?
        deadline.within do
          status, body = @transport.call(uri: uri, request: request, deadline: deadline, max_bytes: MAX_RESPONSE_BYTES)
          raise Error.new(:unavailable) unless status == 200
          raise Error.new(:invalid_response) unless body.is_a?(String) && body.bytesize <= MAX_RESPONSE_BYTES
          data = JSON.parse(body)
          raise Error.new(:invalid_response) unless data.is_a?(Hash)
          raise Error.new(:unavailable) if data.key?("error")
          data
        end
      rescue SearchDeadline::Exceeded, Error
        raise
      rescue JSON::ParserError
        raise Error.new(:invalid_response), cause: nil
      rescue StandardError
        raise Error.new(:unavailable), cause: nil
      end
  end
end

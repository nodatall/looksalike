require "net/http"

module Vision
  class HttpTransport
    def initialize(http_factory: ->(host, port) { Net::HTTP.new(host, port, nil) })
      @http_factory = http_factory
    end

    def call(uri:, request:, deadline:, max_bytes:)
      deadline.within do
        http = @http_factory.call(uri.host, uri.port)
        http.use_ssl = true
        http.max_retries = 0
        http.open_timeout = deadline.remaining
        http.read_timeout = deadline.remaining
        http.write_timeout = deadline.remaining
        request["Accept"] = "application/json"
        request["Accept-Encoding"] = "identity"
        body = +"".b
        status = nil
        http.start do |connection|
          connection.request(request) do |response|
            status = response.code.to_i
            raise Client::Error.new(:unavailable) unless status == 200
            length = response["Content-Length"]
            raise Client::Error.new(:invalid_response) if length && length.to_i > max_bytes
            response.read_body do |chunk|
              deadline.remaining
              raise Client::Error.new(:invalid_response) if body.bytesize + chunk.bytesize > max_bytes
              body << chunk
              http.read_timeout = deadline.remaining
            end
          end
        end
        [ status, body ]
      end
    end
  end
end

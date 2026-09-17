require "test_helper"

class SerpApi::HttpTransportTest < ActiveSupport::TestCase
  class Connection
    attr_accessor :use_ssl, :max_retries, :open_timeout, :read_timeout, :write_timeout
    attr_reader :starts

    def initialize(response)
      @response = response
      @starts = 0
    end

    def start
      @starts += 1
      yield self
    end

    def request(_request)
      yield @response
    end
  end

  class Response
    attr_reader :code
    def initialize(chunks:, length: nil, &advance)
      @chunks, @length, @advance = chunks, length, advance
      @code = "200"
    end

    def [](name)
      @length if name == "Content-Length"
    end

    def read_body
      @chunks.each do |chunk|
        @advance&.call
        yield chunk
      end
    end
  end

  def perform(connection, deadline: SearchDeadline.new, max_bytes: 100)
    transport = SerpApi::HttpTransport.new(http_factory: ->(*) { connection })
    uri = URI("https://serpapi.com/search.json")
    transport.call(uri: uri, request: Net::HTTP::Get.new(uri), deadline: deadline, max_bytes: max_bytes)
  end

  test "sets no retries and remaining budget for all socket timeouts" do
    now = 5.0
    deadline = SearchDeadline.new(clock: -> { now })
    now += 10
    connection = Connection.new(Response.new(chunks: [ "{}" ]))
    assert_equal [ 200, "{}" ], perform(connection, deadline: deadline)
    assert_equal 0, connection.max_retries
    assert_equal 45, connection.open_timeout
    assert_equal 45, connection.read_timeout
    assert_equal 45, connection.write_timeout
    assert_equal true, connection.use_ssl
    assert_equal 1, connection.starts
  end

  test "bounds declared and actual streamed response size" do
    [ Response.new(chunks: [], length: "101"), Response.new(chunks: [ "a" * 70, "b" * 31 ]) ].each do |response|
      assert_raises(SerpApi::Client::Error) { perform(Connection.new(response)) }
    end
  end

  test "slow chunks cannot refresh the whole-call deadline" do
    now = 0.0
    deadline = SearchDeadline.new(clock: -> { now })
    response = Response.new(chunks: [ "a", "b", "c" ]) { now += 20 }
    connection = Connection.new(response)
    assert_raises(SearchDeadline::Exceeded) { perform(connection, deadline: deadline) }
    assert_equal 1, connection.starts
  end
end

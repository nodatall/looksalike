require "test_helper"

class EbaySearchTest < ActiveSupport::TestCase
  class StoreDouble
    attr_reader :reserved, :released
    def lookup(_) = nil
    def acquire(**)
      @reserved = 2
      SearchStore::Grant.new(status: "live", token: "owner", cached_result: nil)
    end
    def release(token) = @released = token
  end

  test "one absolute deadline stops later calls and retains allowance after uncertain work" do
    now, calls = 0.0, []
    store = StoreDouble.new
    transport = ->(uri:, **) do
      calls << uri.path
      now += 30
      body = uri.path == "/image" ? { image_id: "private-ref" } : { search_metadata: { status: "Success" }, visual_matches: [] }
      [ 200, body.to_json ]
    end
    flow = EbaySearch.new(client: SerpApi::Client.new(api_key: "offline-key", transport: transport), store: store,
      enabled: true, clock: -> { now })
    events = []
    result = flow.call(photo: File.binread(file_fixture("photo.jpg")), session_id: "visitor", ip: "127.0.0.1", progress: ->(event) { events << event })
    assert_equal "deadline", result["status"]
    assert_equal %w[/image /search.json], calls
    assert_equal 2, store.reserved
    assert_equal "owner", store.released
    assert_equal 2, result["stages"].length
    assert_equal "failed", events.last["status"]
    refute_match(/private-ref|offline-key/, result.to_json)
  end

  test "a real shared deadline returns failure and completes cleanup after interrupting nested provider work" do
    calls, events = [], []
    store = StoreDouble.new
    store.define_singleton_method(:release) do |token|
      sleep 0.01 # Give a queued duplicate timeout time to interrupt cleanup.
      super(token)
    end
    transport = ->(uri:, deadline:, **) do
      calls << uri.path
      deadline.within { sleep 1 }
      flunk "Timed-out provider work must not finish"
    end
    photo = Tempfile.new("search-deadline")
    photo.binmode
    photo.write(File.binread(file_fixture("photo.jpg")))
    path = photo.path
    flow = EbaySearch.new(client: SerpApi::Client.new(api_key: "offline-key", transport: transport), store: store, enabled: true)
    result = flow.call(photo: photo, session_id: "visitor", ip: "127.0.0.1", deadline: SearchDeadline.new(seconds: 0.1),
      progress: ->(event) { events << event })
    assert_equal "deadline", result["status"]
    assert_equal [ "/image" ], calls
    assert_equal 2, store.reserved
    assert_equal "owner", store.released
    refute File.exist?(path)
    assert_equal [ "upload" ], result["stages"].map { |entry| entry["stage"] }
    assert_equal "failed", result["stages"].last["status"]
    assert_equal "failed", events.last["status"]
    assert_equal({ "uploads" => 1, "serpapi" => 0, "vision" => 0 }, result["attempts"])
  end

  test "disconnect before the next call closes the photo and keeps the reservation without retry" do
    store = StoreDouble.new
    calls = 0
    client = SerpApi::Client.new(api_key: "offline-key", transport: ->(**) { calls += 1; [ 200, { image_id: "private-ref" }.to_json ] })
    photo = Tempfile.new("search-disconnect")
    photo.binmode
    photo.write(File.binread(file_fixture("photo.jpg")))
    path = photo.path
    flow = EbaySearch.new(client: client, store: store, enabled: true)
    result = flow.call(photo: photo, session_id: "visitor", ip: "127.0.0.1", progress: ->(event) {
      raise EbaySearch::Disconnected if event["stage"] == "lens" && event["status"] == "started"
    })
    assert_nil result
    assert_equal 1, calls
    assert_equal 2, store.reserved
    assert_equal "owner", store.released
    refute File.exist?(path)
  end

  test "nonprepared photos and invalid configuration close uploads before reserving or dispatching" do
    [ [ "photo.png", nil ], [ "photo.jpg", SearchSettings::Invalid ] ].each do |name, configuration_error|
      photo = Tempfile.new("search-invalid")
      photo.binmode
      photo.write(File.binread(file_fixture(name)))
      path = photo.path
      store = StoreDouble.new
      flow = EbaySearch.new(store: store, enabled: true)
      invoke = -> { flow.call(photo: photo, session_id: "visitor", ip: "127.0.0.1") }
      previous = ENV["SEARCH_DAILY_ATTEMPT_LIMIT"]
      begin
        ENV["SEARCH_DAILY_ATTEMPT_LIMIT"] = "0" if configuration_error
        result = invoke.call
      ensure
        previous ? ENV["SEARCH_DAILY_ATTEMPT_LIMIT"] = previous : ENV.delete("SEARCH_DAILY_ATTEMPT_LIMIT")
      end
      assert_includes %w[invalid_photo configuration_error], result["status"]
      assert_nil store.reserved
      refute File.exist?(path)
      assert_equal 0, result["attempts"]["serpapi"]
    end
  end
end

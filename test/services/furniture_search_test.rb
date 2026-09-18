require "test_helper"
require_relative "../support/experiment_helpers"

class FurnitureSearchTest < ActiveSupport::TestCase
  include ExperimentHelpers
  setup { prepare_experiment }
  teardown { FileUtils.remove_entry(@temporary) }

  test "shared policies dispatch one or two searches with a separate upload" do
    %w[lens_only lens_then_images].each do |route|
      @calls.clear
      reserved = []
      result = FurnitureSearch.new(client: @client, accounting: ->(stage) { reserved << stage }).call(photo: @photo, zip: "10001", route: route)
      expected = route == "lens_only" ? %w[upload lens] : %w[upload lens images]
      assert_equal "success", result["status"]
      assert_equal expected, reserved
      assert_equal expected.length, @calls.length
      assert_equal 3, result["listings"].length
      assert_equal 3, result.dig("counts", "displayed")
      assert result["stages"].all? { |stage| stage["elapsed_ms"] >= 0 }
      refute_match(/private-upload-reference|offline-secret-key|search_metadata|json_endpoint/, result.to_json)
      assert_equal "site:newyork.craigslist.org", result.dig("parameters", 0, "q") if route == "lens_only"
      assert_equal "New York,New York,United States", result.dig("parameters", 1, "location") if route == "lens_then_images"
    end
  end

  test "weak recognition never makes Images request" do
    calls = 0
    client = SerpApi::Client.new(api_key: "offline-key", transport: ->(uri:, **) do
      calls += 1
      [ 200, uri.path == "/image" ? '{"image_id":"ref"}' : '{"search_metadata":{"status":"Success"},"visual_matches":[]}' ]
    end)
    result = FurnitureSearch.new(client: client, accounting: ->(*) { }).call(photo: @photo, zip: "10001", route: "lens_then_images")
    assert_equal "weak_recognition", result["status"]
    assert_equal 2, calls
  end

  test "invalid ZIP, photo and expired deadline produce no requests or reservations" do
    [ { zip: "00000", photo: @photo }, { zip: "10001", photo: "bad" }, { zip: "10001", photo: @photo, deadline: SearchDeadline.new(seconds: -1) } ].each do |options|
      result = FurnitureSearch.new(client: @client, accounting: ->(*) { flunk "must not reserve" }).call(route: "lens_only", **options)
      refute_equal "success", result["status"]
    end
    assert_empty @calls
  end

  test "timeout after dispatch is counted once and never retried" do
    reserved = []
    calls = 0
    client = SerpApi::Client.new(api_key: "offline-key", transport: ->(uri:, **) do
      calls += 1
      raise Net::ReadTimeout, "private error URL" if uri.path == "/search.json"
      [ 200, '{"image_id":"ref"}' ]
    end)
    result = FurnitureSearch.new(client: client, accounting: ->(stage) { reserved << stage }).call(photo: @photo, zip: "10001", route: "lens_then_images")
    assert_equal %w[upload lens], reserved
    assert_equal 2, calls
    assert_equal "failed", result["status"]
    refute_match(/private|ref|http/, result.to_json)
  end

  test "deadline after upload prevents a search reservation" do
    now = 0.0
    reserved = []
    client = SerpApi::Client.new(api_key: "offline-key", transport: ->(**) { now = 56; [ 200, '{"image_id":"ref"}' ] })
    result = FurnitureSearch.new(client: client, accounting: ->(stage) { reserved << stage }, clock: -> { now }).call(photo: @photo, zip: "10001", route: "lens_only", deadline: SearchDeadline.new(clock: -> { now }))
    assert_equal "deadline", result["status"]
    assert_equal [ "upload" ], reserved
  end

  test "evidence allowlist excludes raw metadata and redacts known secrets and references" do
    client = SerpApi::Client.new(api_key: "offline-secret-key", transport: ->(uri:, **) do
      body = if uri.path == "/image"
        { "image_id" => "private-upload-reference" }
      else
        { "search_metadata" => { "status" => "Success", "private" => "private-provider-payload" },
          "related_content" => [ { "query" => "chair https://example.com/?api_key=foreign-secret", "link" => "https://evil.example/private" } ],
          "visual_matches" => [ candidates.first.merge("title" => "Chair offline-secret-key private-upload-reference", "account_email" => "private@example.com") ] }
      end
      [ 200, body.to_json ]
    end)
    result = FurnitureSearch.new(client: client, accounting: ->(*) { }).call(photo: @photo, zip: "10001", route: "lens_only")
    assert_equal "success", result["status"]
    refute_match(/offline-secret-key|private-upload-reference|private-provider-payload|private@example|foreign-secret|evil.example/, result.to_json)
    assert_equal "chair [URL omitted]", result.dig("excerpts", "related_queries", 0)
  end
  test "actual short query feeds Images after exactly one upload and one Lens call" do
    titles = JSON.parse(file_fixture("modern_sofa_titles.json").read)
    calls = []
    client = SerpApi::Client.new(api_key: "offline-key", transport: ->(uri:, **) do
      params = URI.decode_www_form(uri.query.to_s).to_h
      calls << [ uri.path, params["engine"] ]
      body = if uri.path == "/image"
        { "image_id" => "offline-ref" }
      elsif params["engine"] == "google_lens"
        { "search_metadata" => { "status" => "Success" }, "visual_matches" => titles.map { |title| { "title" => title } } }
      else
        assert_equal "green velvet sofa site:sfbay.craigslist.org", params["q"]
        assert_equal "San Francisco,California,United States", params["location"]
        { "search_metadata" => { "status" => "Success" }, "images_results" => [] }
      end
      [ 200, body.to_json ]
    end)
    result = FurnitureSearch.new(client: client, accounting: ->(*) { }).call(photo: @photo, zip: "94103", route: "lens_then_images")
    assert_equal "success", result["status"]
    assert_equal "green velvet sofa", result["interpretation"]
    assert_equal [ [ "/image", nil ], [ "/search.json", "google_lens" ], [ "/search.json", "google_images" ] ], calls
  end
end

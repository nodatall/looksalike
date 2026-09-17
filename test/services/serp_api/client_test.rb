require "test_helper"

class SerpApi::ClientTest < ActiveSupport::TestCase
  def client(transport: nil)
    options = { api_key: "offline-test-key" }
    options[:transport] = transport if transport
    SerpApi::Client.new(**options)
  end

  def lens(client_instance = client, deadline: SearchDeadline.new)
    client_instance.lens(image_id: "offline-image-ref", type: "visual_matches", query: "site:sfbay.craigslist.org", deadline: deadline)
  end

  test "upload is binary multipart on singular image endpoint" do
    bytes = Vips::Image.black(24, 16, bands: 3).write_to_buffer(".jpg")
    request = stub_request(:post, "https://serpapi.com/image").with do |req|
      req.headers["Content-Type"].start_with?("multipart/form-data; boundary=") &&
        req.body.b.include?(bytes) && req.body.include?('name="image"; filename="photo.jpeg"') &&
        req.body.include?("Content-Type: image/jpeg\r\n") && req.body.include?("offline-test-key")
    end.to_return(status: 200, body: { image_id: "offline-image-ref" }.to_json)
    assert_equal "offline-image-ref", client.upload(photo: bytes, deadline: SearchDeadline.new)
    assert_requested request, times: 1
  end

  test "Lens and Images use explicit engines and parameters" do
    lens_request = stub_request(:get, "https://serpapi.com/search.json").with(query: {
      engine: "google_lens", image_id: "offline-image-ref", type: "visual_matches",
      country: "us", hl: "en", q: "site:sfbay.craigslist.org", api_key: "offline-test-key"
    }).to_return(status: 200, body: { search_metadata: { status: "Success" }, visual_matches: [] }.to_json)
    assert_equal [], lens["visual_matches"]
    assert_requested lens_request, times: 1
    image_request = stub_request(:get, "https://serpapi.com/search.json").with(query: {
      engine: "google_images", q: "wood chair site:chicago.craigslist.org", location: "Chicago,Illinois,United States",
      gl: "us", hl: "en", api_key: "offline-test-key"
    }).to_return(status: 200, body: { search_metadata: { status: "Success" } }.to_json)
    client.images(query: "wood chair site:chicago.craigslist.org", location: "Chicago,Illinois,United States", deadline: SearchDeadline.new)
    assert_requested image_request, times: 1
  end

  test "rejects nonobjects, malformed JSON, provider errors, and incomplete search metadata safely" do
    [ "[]", "null", "not json", '{"error":"private provider details"}', "{}", '{"search_metadata":{"status":"Processing"}}', '{"search_metadata":[]}' ].each do |body|
      error = assert_raises(SerpApi::Client::Error) { lens(client(transport: ->(**) { [ 200, body ] })) }
      refute_match(/private|offline-test-key|offline-image-ref|https:/, error.message)
      assert_nil error.cause
    end
  end

  test "rejects missing upload image ID before it could feed Lens" do
    bytes = Vips::Image.black(2, 2).write_to_buffer(".png")
    assert_raises(SerpApi::Client::Error) { client(transport: ->(**) { [ 200, "{}" ] }).upload(photo: bytes, deadline: SearchDeadline.new) }
  end

  test "does not retry timeouts or follow redirects" do
    timeout = stub_request(:get, %r{\Ahttps://serpapi.com/search.json}).to_timeout
    assert_raises(SerpApi::Client::Error) { lens }
    assert_requested timeout, times: 1
    WebMock.reset!
    redirect = stub_request(:get, %r{\Ahttps://serpapi.com/search.json}).to_return(status: 302, headers: { "Location" => "https://other.example/" })
    assert_raises(SerpApi::Client::Error) { lens }
    assert_requested redirect, times: 1
    assert_not_requested :get, "https://other.example/"
  end

  test "invalid photos do not dispatch and transport exceptions are sanitized" do
    calls = 0
    transport = ->(**) { calls += 1; raise IOError, "private credential URL" }
    instance = client(transport: transport)
    assert_raises(PhotoValidator::Invalid) { instance.upload(photo: "not a photo", deadline: SearchDeadline.new) }
    assert_equal 0, calls
    error = assert_raises(SerpApi::Client::Error) { lens(instance) }
    assert_nil error.cause
    refute_match(/private|credential/, error.message)
    assert_equal 1, calls
  end

  test "sequential calls share the same absolute deadline" do
    now = 0.0
    calls = 0
    transport = ->(**) { calls += 1; now += 30; [ 200, '{"search_metadata":{"status":"Success"}}' ] }
    deadline = SearchDeadline.new(clock: -> { now })
    instance = client(transport: transport)
    lens(instance, deadline: deadline)
    assert_raises(SearchDeadline::Exceeded) { lens(instance, deadline: deadline) }
    assert_equal 2, calls
    assert_raises(SearchDeadline::Exceeded) { lens(instance, deadline: deadline) }
    assert_equal 2, calls
  end

  test "unconfigured client never dispatches and default transport cannot bill in tests" do
    transport = ->(**) { flunk "must not dispatch" }
    assert_raises(SerpApi::Client::Error) { lens(SerpApi::Client.new(api_key: "", transport: transport)) }
    assert_raises(WebMock::NetConnectNotAllowedError) { lens }
  end
  test "account summary excludes identities and credentials and validates total allowance" do
    payload = { "account_status" => "Active", "total_searches_left" => 27, "plan_searches_left" => 2,
      "extra_credits" => 25, "api_key" => "private-key", "account_email" => "private@example.com",
      "account_id" => "private-account", "plan_renewal_date" => "2026-10-17 00:00:00 UTC" }
    summary = client(transport: ->(uri:, **) { assert_equal "/account.json", uri.path; [ 200, payload.to_json ] }).account(deadline: SearchDeadline.new)
    assert_equal 27, summary["total_searches_left"]
    assert_equal 25, summary["extra_credits"]
    refute_match(/private|account_email|account_id|api_key/, summary.to_json)
    [ nil, "27", -1, 2.5 ].each do |value|
      payload["total_searches_left"] = value
      assert_raises(SerpApi::Client::Error) { client(transport: ->(**) { [ 200, payload.to_json ] }).account(deadline: SearchDeadline.new) }
    end
  end
end

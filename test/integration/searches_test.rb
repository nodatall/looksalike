require "test_helper"

class SearchesTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  def setup
    SearchCacheEntry.delete_all
    SearchUsageReservation.delete_all
    SearchLease.delete_all
    SearchLease.create!(id: 1)
    @env = ENV.slice("LIVE_SEARCH_ENABLED", "SERPAPI_API_KEY", "VENICE_API_KEY")
    ENV.update("LIVE_SEARCH_ENABLED" => "true", "SERPAPI_API_KEY" => "offline-serp-key", "VENICE_API_KEY" => "offline-vision-key")
    @csrf_setting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get root_path
    @csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
  end

  def teardown
    ActionController::Base.allow_forgery_protection = @csrf_setting
    %w[LIVE_SEARCH_ENABLED SERPAPI_API_KEY VENICE_API_KEY].each { |name| @env.key?(name) ? ENV[name] = @env[name] : ENV.delete(name) }
    SearchCacheEntry.delete_all
    SearchUsageReservation.delete_all
    SearchLease.delete_all
    SearchLease.create!(id: 1)
    super
  end

  def upload_request
    stub_request(:post, "https://serpapi.com/image").to_return(status: 200, body: { image_id: "private-photo-reference" }.to_json)
  end

  def lens_request(titles: [ "green velvet sofa", "green velvet couch" ], status: 200)
    stub_request(:get, "https://serpapi.com/search.json").with(query: {
      engine: "google_lens", image_id: "private-photo-reference", type: "all", country: "us", hl: "en", api_key: "offline-serp-key"
    }).to_return(status: status, body: { search_metadata: { status: "Success" }, visual_matches: titles.map { |title| { title: title } } }.to_json)
  end

  def ebay_request(query: "green velvet sofa", rows: nil)
    rows ||= 7.times.map { |index| { title: "Green velvet sofa", link: "https://www.ebay.com/itm/#{index + 100}",
      thumbnail: "https://i.ebayimg.com/images/#{index}.jpg", location: "Located in United States", price: { raw: "$100" } } }
    stub_request(:get, "https://serpapi.com/search.json").with(query: {
      engine: "ebay", _nkw: query, ebay_domain: "ebay.com", _ipg: "25", api_key: "offline-serp-key"
    }).to_return(status: 200, body: { search_metadata: { status: "Success" }, organic_results: rows }.to_json)
  end

  def submit(csrf: @csrf, photo_name: "photo.jpg")
    post searches_path, params: { photo: Rack::Test::UploadedFile.new(file_fixture(photo_name), "image/jpeg") }, headers: { "X-CSRF-Token" => csrf }
  end

  def events
    response.body.lines.map { |line| JSON.parse(line) }
  end

  test "CSRF-protected upload streams real ordered stages and cached reload makes no new calls" do
    references = [ "https://example.test/photo", "HTTPS://example.test/photo", "http:example", "HtTpS:",
      "data:image/jpeg;base64,private", "DATA:private" ]
    titles = references.map { |reference| "Green velvet sofa #{reference}" }
    rows = titles.each_with_index.map { |title, index| { title: title, link: "https://www.ebay.com/itm/#{index + 100}",
      thumbnail: "https://i.ebayimg.com/images/#{index}.jpg", location: "Located in United States", price: { raw: "$100" } } }
    rows << rows.first.merge(link: "https://www.ebay.com/itm/200", title: "Green velvet sofa")
    upload, lens, ebay = upload_request, lens_request(titles: titles), ebay_request(rows: rows)
    submit
    assert_response :success
    assert_equal "application/x-ndjson", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert response.headers["Last-Modified"]
    result = events.last.fetch("result")
    assert_equal "success", result["status"]
    assert_equal EbaySearch::VERSION, result["version"]
    assert_equal 7, result["listings"].length
    assert_equal({ "uploads" => 1, "serpapi" => 2, "vision" => 0 }, result["attempts"])
    assert_equal %w[upload upload lens lens ebay ebay filter filter], events[0...-1].map { |event| event["stage"] }
    assert_equal %w[started complete] * 4, events[0...-1].map { |event| event["status"] }
    assert_equal "skipped", result["stages"].find { |stage| stage["stage"] == "vision" }["status"]
    assert_equal 7, result["stages"].last.dig("summary", "returned")
    %w[lens ebay].each do |name|
      assert_equal Array.new(6, "Green velvet sofa [URL omitted]"), result["stages"].find { |stage| stage["stage"] == name }.dig("summary", "titles")
    end
    assert_equal Array.new(6, "Green velvet sofa [URL omitted]") + [ "Green velvet sofa" ], result["listings"].map { |listing| listing["title"] }
    refute_match(/offline-serp-key|offline-vision-key|private-photo-reference|image_id|search_metadata/, response.body)
    assert_equal 2, SearchUsageReservation.where(kind: "serpapi").sum(:units)
    submit
    cached = events.last.fetch("result")
    assert_equal 1, events.length
    assert_equal "cache", cached["source"]
    assert_equal result["retrieved_at"], cached["retrieved_at"]
    assert_equal result["listings"], cached["listings"]
    assert_equal({ "uploads" => 0, "serpapi" => 0, "vision" => 0 }, cached["attempts"])
    assert_equal result["attempts"], cached["original_attempts"]
    [ upload, lens, ebay ].each { |request| assert_requested request, times: 1 }
    assert_not_requested :post, Vision::Client::ENDPOINT
  end

  test "weak Lens uses one durably reserved vision call and then eBay" do
    upload_request
    lens_request(titles: [ "sofa", "couch" ])
    vision = stub_request(:post, Vision::Client::ENDPOINT).with do |request|
      assert_equal 1, SearchUsageReservation.where(kind: "vision").count
      assert_equal 3, SearchUsageReservation.where(kind: "vision").sum(:reserved_cents)
      data = JSON.parse(request.body)
      assert_equal Vision::Client::MODEL, data["model"]
      true
    end.to_return(status: 200, body: { model: Vision::Client::MODEL, choices: [ { finish_reason: "stop", message: {
      role: "assistant", content: { status: "recognized", category: "sofa", traits: [ "carved wood", "curved" ] }.to_json } } ] }.to_json)
    ebay_request(query: "carved wood curved sofa")
    submit
    result = events.last["result"]
    assert_equal "success", result["status"]
    assert_equal "vision", result.dig("query_preparation", "source")
    assert_equal %w[upload lens vision ebay filter], events.select { |event| event["status"] == "started" }.map { |event| event["stage"] }
    assert_equal 1, result["attempts"]["vision"]
    assert_requested vision, times: 1
  end

  test "provider failure stops without retry and the full search reservation remains" do
    upload = upload_request
    lens = lens_request(status: 503)
    submit
    assert_equal "provider_unavailable", events.last.dig("result", "status")
    assert_equal 2, SearchUsageReservation.sum(:units)
    assert_equal 0, SearchCacheEntry.count
    assert_nil SearchLease.find(1).owner_token
    assert_requested upload, times: 1
    assert_requested lens, times: 1
    assert_not_requested(:get, "https://serpapi.com/search.json", query: hash_including(engine: "ebay"))
  end

  test "recognition rejection skips eBay and empty eBay responses cache as empty results" do
    upload_request
    lens_request(titles: [ "sofa", "couch" ])
    vision = stub_request(:post, Vision::Client::ENDPOINT).to_return(status: 200, body: { model: Vision::Client::MODEL,
      choices: [ { finish_reason: "stop", message: { role: "assistant", content: { status: "unclear", category: nil, traits: [] }.to_json } } ] }.to_json)
    submit
    assert_equal "unclear", events.last.dig("result", "status")
    assert_equal 0, SearchCacheEntry.count
    assert_not_requested(:get, "https://serpapi.com/search.json", query: hash_including(engine: "ebay"))
    assert_requested vision, times: 1
    WebMock.reset!
    upload_request
    lens_request
    ebay = ebay_request(rows: [])
    submit
    assert_equal "empty", events.last.dig("result", "status")
    assert_empty events.last.dig("result", "listings")
    submit
    assert_equal "cache", events.last.dig("result", "source")
    assert_requested ebay, times: 1
  end

  test "missing CSRF disabled live mode and nonprepared photos never dispatch or reserve" do
    submit(csrf: "invalid")
    assert_response :unprocessable_entity
    submit(photo_name: "photo.png")
    assert_equal "invalid_photo", events.last.dig("result", "status")
    ENV["LIVE_SEARCH_ENABLED"] = "false"
    submit
    assert_equal "disabled", events.last.dig("result", "status")
    assert_equal 0, SearchUsageReservation.count
    assert_not_requested :post, "https://serpapi.com/image"
  end
end

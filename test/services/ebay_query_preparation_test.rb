require "test_helper"

class EbayQueryPreparationTest < ActiveSupport::TestCase
  class Client
    attr_reader :calls
    def initialize(&implementation)
      @implementation = implementation
      @calls = 0
    end

    def recognize(**args)
      @calls += 1
      @implementation.call(**args)
    end
  end

  def lens(title = "coffee table")
    { "visual_matches" => [ { "title" => title }, { "title" => title } ] }
  end

  def response(status: "recognized", category: "coffee table", traits: [ "curved legs" ])
    Vision::Client::Result.new(answer: { "status" => status, "category" => category, "traits" => traits }, usage: { "input_tokens" => 100 })
  end

  test "accepted Lens phrase is preserved with no vision or photo work" do
    client = Client.new { flunk "no vision" }
    result = EbayQueryPreparation.new(vision_client: client).call(lens_response: lens("wood coffee table"), photo: "not decoded", deadline: SearchDeadline.new, before_vision_dispatch: nil)
    assert_equal "ready", result.status
    assert_equal "wood coffee table", result.query
    assert_equal "lens", result.source
    assert_equal 0, client.calls
  end

  test "missing and bare category phrases make exactly one vision call with explicit recorder" do
    [ {}, lens, lens("sofa") ].each do |lens_response|
      callback = ->(_) { true }
      client = Client.new do |photo:, deadline:, before_dispatch:|
        assert_equal "prepared-photo", photo
        assert_same callback, before_dispatch
        assert_operator deadline.remaining, :<=, 15
        response
      end
      result = EbayQueryPreparation.new(vision_client: client).call(lens_response: lens_response, photo: "prepared-photo", deadline: SearchDeadline.new, before_vision_dispatch: callback)
      assert_equal "ready", result.status
      assert_equal "curved legs coffee table", result.query
      assert_equal "vision", result.source
      assert_equal Vision::Client::MODEL, result.metadata[:model]
      assert_equal [ "curved legs" ], result.metadata[:traits]
      assert_equal 1, client.calls
    end
  end

  test "vision receives smaller remaining budget and preserves ten seconds for eBay" do
    now = 0.0
    clock = -> { now }
    deadline = SearchDeadline.new(clock: clock)
    now = 38.0
    client = Client.new do |deadline:, **|
      assert_equal 7.0, deadline.remaining
      now += 6.0
      response
    end
    result = EbayQueryPreparation.new(vision_client: client, clock: clock).call(lens_response: lens, photo: "photo", deadline: deadline, before_vision_dispatch: ->(_) { true })
    assert_equal "ready", result.status
    assert_equal 11.0, deadline.remaining
    assert_equal 6000, result.metadata[:duration_ms]
  end

  test "insufficient time stops before vision and timeouts never retry" do
    [ 9, 10 ].each do |seconds|
      client = Client.new { flunk "no dispatch" }
      result = EbayQueryPreparation.new(vision_client: client).call(lens_response: lens, photo: "photo", deadline: SearchDeadline.new(seconds: seconds), before_vision_dispatch: nil)
      assert_equal "insufficient_time", result.status
      assert_equal 0, client.calls
    end
    now = 0.0
    clock = -> { now }
    client = Client.new { |**| now += 16; response }
    result = EbayQueryPreparation.new(vision_client: client, clock: clock).call(lens_response: lens, photo: "photo", deadline: SearchDeadline.new(clock: clock), before_vision_dispatch: nil)
    assert_equal "timeout", result.status
    assert_nil result.query
    assert_equal 1, client.calls
  end

  test "real client composes with policy and preserves one recorded offline request" do
    reservations = []
    output = { status: "recognized", category: "dining chair", traits: [ "curved back", "wood" ] }
    body = { model: Vision::Client::MODEL, status: "completed", output: [
      { type: "message", role: "assistant", status: "completed", content: [ { type: "output_text", text: output.to_json } ] }
    ], usage: { input_tokens: 123, output_tokens: 20, total_tokens: 143 } }
    request = stub_request(:post, Vision::Client::ENDPOINT).to_return(status: 200, body: body.to_json)
    result = EbayQueryPreparation.new(vision_client: Vision::Client.new(api_key: "offline-key")).call(
      lens_response: {}, photo: File.binread(Rails.root.join("test/fixtures/files/photo.jpg")),
      deadline: SearchDeadline.new, before_vision_dispatch: ->(metadata) { reservations << metadata; true }
    )
    assert_equal "ready", result.status
    assert_equal "curved back wood dining chair", result.query
    assert_equal 1, reservations.size
    assert_equal "0.02", reservations.first[:reserved_usd]
    assert_equal 143, result.metadata[:usage]["total_tokens"]
    refute_match(/offline-key|base64|output_text/, result.inspect)
    assert_requested request, times: 1
  end

  test "unclear unsafe and provider failures have no downstream query or raw output" do
    [ [ response(status: "unclear", category: nil, traits: []), "unclear" ],
      [ response(status: "not_furniture", category: nil, traits: []), "not_furniture" ],
      [ response(traits: [ "secret:https://bad.test" ]), "invalid_answer" ] ].each do |answer, status|
      client = Client.new { |**| answer }
      result = EbayQueryPreparation.new(vision_client: client).call(lens_response: lens, photo: "photo", deadline: SearchDeadline.new, before_vision_dispatch: nil)
      assert_equal status, result.status
      assert_nil result.query
      refute_match(/secret|https/, result.inspect)
      assert_equal 1, client.calls
    end
    client = Client.new { |**| raise Vision::Client::Error.new(:refused) }
    result = EbayQueryPreparation.new(vision_client: client).call(lens_response: lens, photo: "photo", deadline: SearchDeadline.new, before_vision_dispatch: nil)
    assert_equal "refused", result.status
    assert_nil result.query
    assert_equal 1, client.calls
  end
end

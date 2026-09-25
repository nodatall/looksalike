require "test_helper"

class Vision::ClientTest < ActiveSupport::TestCase
  def photo
    @photo ||= File.binread(Rails.root.join("test/fixtures/files/photo.jpg"))
  end

  def payload
    { model: Vision::Client::MODEL, status: "completed", output: [
      { type: "message", role: "assistant", status: "completed", content: [
        { type: "output_text", text: { status: "recognized", category: "sofa", traits: [ "carved wood" ] }.to_json }
      ] }
    ], usage: { input_tokens: 123, output_tokens: 20, total_tokens: 143, private_field: "secret" } }
  end

  def client(transport: nil, api_key: "offline-vision-key")
    options = { api_key: api_key }
    options[:transport] = transport if transport
    Vision::Client.new(**options)
  end

  def recognize(instance = client, before_dispatch: ->(_) { true }, bytes: photo, deadline: SearchDeadline.new)
    instance.recognize(photo: bytes, deadline: deadline, before_dispatch: before_dispatch)
  end

  test "fixed structured Responses request uses validated inline JPEG and records before dispatch" do
    events = []
    request = stub_request(:post, Vision::Client::ENDPOINT).with do |req|
      events << :dispatch
      data = JSON.parse(req.body)
      assert_equal "Bearer offline-vision-key", req.headers["Authorization"]
      assert_equal Vision::Client::MODEL, data["model"]
      assert_equal false, data["store"]
      assert_equal 300, data["max_output_tokens"]
      refute data.key?("tools")
      format = data.dig("text", "format")
      assert_equal true, format["strict"]
      assert_equal "json_schema", format["type"]
      assert_equal false, format.dig("schema", "additionalProperties")
      assert_equal PhotoQuery::CATEGORIES + [ nil ], format.dig("schema", "properties", "category", "enum")
      image = data.dig("input", 0, "content", 1)
      assert_equal "auto", image["detail"]
      assert_equal photo, Base64.strict_decode64(image["image_url"].delete_prefix("data:image/jpeg;base64,"))
      true
    end.to_return(status: 200, body: payload.to_json)
    result = recognize(before_dispatch: ->(metadata) { events << :reserve; assert_equal "0.02", metadata[:reserved_usd]; true })
    assert_equal [ :reserve, :dispatch ], events
    assert_equal "sofa", result.answer["category"]
    assert_equal({ "input_tokens" => 123, "output_tokens" => 20, "total_tokens" => 143 }, result.usage)
    refute_match(/carved|123/, result.inspect)
    assert_requested request, times: 1
  end

  test "unconfigured invalid and unprepared photos never reserve or dispatch" do
    transport = ->(**) { flunk "no dispatch" }
    callback = ->(_) { flunk "no reservation" }
    assert_raises(Vision::Client::Error) { recognize(client(transport: transport, api_key: ""), before_dispatch: callback) }
    assert_raises(PhotoValidator::Invalid) { recognize(client(transport: transport), bytes: "junk", before_dispatch: callback) }
    [ Vips::Image.black(2, 2).write_to_buffer(".png"), Vips::Image.black(1601, 1).write_to_buffer(".jpg") ].each do |bytes|
      error = assert_raises(Vision::Client::Error) { recognize(client(transport: transport), bytes: bytes, before_dispatch: callback) }
      assert_equal :invalid_photo, error.code
    end
  end

  test "missing rejected and failed reservations fail closed and redact cause" do
    [ nil, ->(_) { false }, ->(_) { nil }, ->(_) { raise "offline-vision-key photo secret" } ].each do |callback|
      error = assert_raises(Vision::Client::Error) { recognize(client(transport: ->(**) { flunk "no dispatch" }), before_dispatch: callback) }
      assert_equal :accounting_unavailable, error.code
      assert_nil error.cause
      refute_match(/offline-vision-key|secret/, error.full_message)
    end
  end

  test "timeout during reservation remains a timeout and never dispatches" do
    assert_raises(SearchDeadline::Exceeded) do
      recognize(client(transport: ->(**) { flunk "no dispatch" }), before_dispatch: ->(_) { raise SearchDeadline::Exceeded })
    end
  end

  test "rejects malformed incomplete refused or unexpected output shapes safely" do
    cases = [ [ "[]", :invalid_response ], [ "null", :invalid_response ], [ "bad-json", :invalid_response ],
      [ payload.merge(error: { message: "secret" }).to_json, :unavailable ],
      [ payload.merge(status: "incomplete").to_json, :incomplete ],
      [ payload.merge(status: "failed").to_json, :invalid_response ],
      [ payload.merge(model: "another-model").to_json, :invalid_response ],
      [ payload.merge(output: []).to_json, :invalid_response ],
      [ payload.merge(output: [ { type: "function_call", arguments: "secret" } ]).to_json, :invalid_response ] ]
    [ { type: "refusal", refusal: "secret" }, { type: "output_text", text: "[]" }, { type: "output_text", text: "secret" } ].each do |content|
      data = payload
      data[:output][0][:content] = [ content ]
      cases << [ data.to_json, content[:type] == "refusal" ? :refused : :invalid_response ]
    end
    cases.each do |body, code|
      error = assert_raises(Vision::Client::Error) { recognize(client(transport: ->(**) { [ 200, body ] })) }
      assert_equal code, error.code
      assert_nil error.cause
      refute_match(/secret|offline-vision-key|base64/, error.full_message)
    end
  end

  test "response limit and transport failures are sanitized without retry" do
    [ ->(**) { [ 200, "a" * (Vision::Client::MAX_RESPONSE_BYTES + 1) ] },
      ->(**) { raise IOError, "offline-vision-key base64 secret" } ].each do |transport|
      error = assert_raises(Vision::Client::Error) { recognize(client(transport: transport)) }
      assert_nil error.cause
      refute_match(/offline-vision-key|base64|secret/, error.full_message)
    end
    timeout = stub_request(:post, Vision::Client::ENDPOINT).to_timeout
    assert_raises(Vision::Client::Error) { recognize }
    assert_requested timeout, times: 1
    WebMock.reset!
    redirect = stub_request(:post, Vision::Client::ENDPOINT).to_return(status: 302, headers: { "Location" => "https://other.example/" })
    assert_raises(Vision::Client::Error) { recognize }
    assert_requested redirect, times: 1
    assert_not_requested :post, "https://other.example/"
    refute_match(/offline-vision-key/, client.inspect)
    refute_match(/offline-vision-key/, client.to_s)
  end

  test "reservation delay cannot dispatch beyond deadline and usage only exposes valid integers" do
    now = 0.0
    deadline = SearchDeadline.new(seconds: 15, clock: -> { now })
    assert_raises(SearchDeadline::Exceeded) do
      recognize(client(transport: ->(**) { flunk "no dispatch" }), deadline: deadline, before_dispatch: ->(_) { now = 16; true })
    end
    data = payload.merge(usage: { input_tokens: "123", output_tokens: -1, total_tokens: 123 })
    result = recognize(client(transport: ->(**) { [ 200, data.to_json ] }))
    assert_equal({ "total_tokens" => 123 }, result.usage)
  end
end

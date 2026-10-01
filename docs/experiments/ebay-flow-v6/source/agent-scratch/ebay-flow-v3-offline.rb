#!/usr/bin/env ruby
require_relative 'ebay-flow-v3'
require 'tmpdir'
require 'minitest/autorun'

# This executable cannot issue requests, even if injection is accidentally bypassed.
class Net::HTTP
  def start(*) = raise('LIVE NETWORK FORBIDDEN IN OFFLINE CHECKS')
end
class SerpApi::HttpTransport
  def call(**) = raise('LIVE NETWORK FORBIDDEN IN OFFLINE CHECKS')
end

class Vision::HttpTransport
  def call(**) = raise('LIVE NETWORK FORBIDDEN IN OFFLINE CHECKS')
end

class VisionFakeClient
  attr_reader :calls
  attr_accessor :failure, :assert_reserved
  def initialize = @calls = []
  def recognize(photo:, deadline:, before_dispatch:)
    raise 'Missing reservation' unless before_dispatch.call(Vision::Client.metadata) == true
    @assert_reserved.call if @assert_reserved
    @calls << 'vision'
    raise Vision::Client::Error.new(:unavailable) if failure == :provider
    raise SearchDeadline::Exceeded if failure == :timeout
    answer = failure == :unclear ? {'status'=>'unclear','category'=>nil,'traits'=>[]} : {'status'=>'recognized','category'=>'sofa','traits'=>['carved wood','curved']}
    Vision::Client::Result.new(answer: answer, usage: {'input_tokens'=>900, 'output_tokens'=>40, 'total_tokens'=>940})
  end
end

class FlowFakeClient
  attr_reader :calls
  attr_accessor :failure, :expected_query
  def initialize = @calls = []
  def redact(value) = value.gsub('fake-secret', '[redacted]')
  def account(deadline:) = {'account_status' => 'Active', 'total_searches_left' => 238}
  def upload(photo:, deadline:)
    @calls << 'upload'
    'private-image-id'
  end
  def lens(image_id:, type:, deadline:)
    @calls << 'lens'
    raise SearchDeadline::Exceeded if failure == :timeout
    return {'related_content' => [{'query' => 'sofa'}], 'visual_matches' => [{'title' => 'sofa'}]} if failure == :weak
    {'related_content' => [{'query' => 'green velvet sofa'}], 'visual_matches' => [{'title' => 'green velvet sofa private-image-id fake-secret https://private.test/image'}, {'title' => 'green velvet couch'}]}
  end
  def ebay(params:, deadline:)
    @calls << 'ebay'
    raise 'Unwanted request filter' unless params == {'engine' => 'ebay', '_nkw' => (expected_query || 'green velvet sofa'), 'ebay_domain' => 'ebay.com', '_ipg' => '25'}
    {'search_metadata' => {'status' => 'Success'}, 'organic_results' => 6.times.map { |i| {'title' => "Sofa #{i}", 'link' => "https://www.ebay.com/itm/#{1000+i}", 'thumbnail' => "https://i.ebayimg.com/images/#{i}.jpg", 'location' => 'Located in United States', 'sponsored' => i == 0} }}
  end
end

class EbayFlowOfflineTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir('ebay-flow-offline-')
    @ledger = File.join(@tmp, 'ledger.sqlite3')
    # SQLite snapshot avoids copying a live WAL inconsistently. Source stays read-only.
    source = SQLite3::Database.new(Rails.root.join('storage/feasibility-v1.sqlite3').to_s, readonly: true)
    source.execute('VACUUM INTO ?', @ledger)
    source.close
    @client = FlowFakeClient.new
    @vision = VisionFakeClient.new
    @runner = EbayFlowV3::Runner.new(ledger: @ledger, directory: File.join(@tmp, 'evidence'), client: @client, vision_client: @vision)
    @runner.freeze!
    @runner.account!
  end
  def teardown = FileUtils.remove_entry(@tmp)
  def score(id, result, good: true)
    @runner.score(id, {'items' => result.fetch('first_six').map { |row| {'url' => row['url'], 'relevant' => good, 'accessible' => true, 'notes' => 'offline fixture judgment'} }})
  end
  def test_full_budget_and_restart_guards
    ids = @runner.photos.map { |x| x['id'] }
    ids.each do |id|
      result = @runner.execute(id)
      assert_equal 'success', result['status']
      assert_equal 6, result['candidates'].size # Price intentionally absent.
      assert_equal true, result['first_six'][0]['sponsored']
      refute_match(/fake-secret|private-image-id/, JSON.generate(result))
      assert_raises(RuntimeError) { @runner.execute(id) }
      assert score(id, result)['passed']
      assert_raises(RuntimeError) { score(id, result) }
    end
    pre = @runner.preflight
    assert_equal 10, pre[:new_searches]
    assert_equal 5, pre[:uploads]
    assert_equal 15, @client.calls.size
    assert_empty @vision.calls
    assert_equal 0, pre[:vision_attempts]
    assert_equal 5, pre[:scored_cases]
    assert_raises(RuntimeError) { @runner.execute(ids.last) }
  end
  def test_two_failures_stop_later_cases
    @client.failure = :timeout
    @runner.photos.first(2).each do |entry|
      result = @runner.execute(entry['id'])
      assert_equal 'deadline', result['status']
      assert_equal %w[upload lens], result['stages'].map { |x| x['stage'] }
      refute score(entry['id'], result)['passed']
    end
    assert_raises(RuntimeError) { @runner.execute('dining-chair') }
    assert_equal 2, @runner.preflight[:new_searches]
    assert_equal 4, @client.calls.size
  end
  def test_weak_recognition_uses_one_reserved_vision_then_ebay
    @client.failure = :weak
    @client.expected_query = 'carved wood curved sofa'
    @vision.assert_reserved = lambda do
      db = @runner.db
      row = @runner.rows(db, EbayFlowV3::ATTEMPT_TABLE).last
      assert_equal 'vision', row['stage']
      assert_nil row['outcome']
      assert_equal '0.03', JSON.parse(row['parameters'])['reserved_usd']
      db.close
    end
    result = @runner.execute('ornate-sofa')
    assert_equal 'success', result['status']
    assert_equal 'vision', result['query_source']
    assert_equal 'carved wood curved sofa', result['interpretation']
    assert_equal %w[upload lens vision ebay], result['stages'].map { |r| r['stage'] }
    assert_equal 940, result['query_preparation'][:metadata][:usage]['total_tokens']
    assert_equal 2, @runner.preflight[:new_searches]
    assert_equal 1, @runner.preflight[:vision_attempts]
    assert_equal 0.03, @runner.preflight[:vision_reserved_usd]
    assert_equal ['vision'], @vision.calls
  end
  def test_vision_failure_blocks_ebay_and_retry
    @client.failure = :weak
    @vision.failure = :provider
    result = @runner.execute('ornate-sofa')
    assert_equal 'unavailable', result['status']
    assert_equal %w[upload lens], @client.calls
    assert_equal ['vision'], @vision.calls
    assert_equal 1, @runner.preflight[:new_searches]
    assert_equal 1, @runner.preflight[:vision_attempts]
    assert_raises(RuntimeError) { @runner.execute('ornate-sofa') }
    refute score('ornate-sofa', result)['passed']
  end
  def test_unclear_vision_blocks_ebay
    @client.failure = :weak
    @vision.failure = :unclear
    result = @runner.execute('ornate-sofa')
    assert_equal 'unclear', result['status']
    assert_equal %w[upload lens], @client.calls
    assert_equal 1, @runner.preflight[:vision_attempts]
  end
  def test_five_vision_calls_reserve_total_fifteen_cents
    @client.failure = :weak
    @client.expected_query = 'carved wood curved sofa'
    @runner.photos.each do |entry|
      result = @runner.execute(entry['id'])
      assert_equal 'success', result['status']
      assert score(entry['id'], result)['passed']
    end
    assert_equal 5, @runner.preflight[:vision_attempts]
    assert_equal 0.15, @runner.preflight[:vision_reserved_usd]
    db = @runner.db(writable: true)
    _, sha = @runner.manifest(db)
    assert_raises(SQLite3::ConstraintException) do
      db.execute("INSERT INTO #{EbayFlowV3::ATTEMPT_TABLE}(case_id,stage,manifest_sha256,parameters,reserved_at) VALUES(?,?,?,?,?)", ['extra', 'vision', sha, '{}', Time.now.utc.iso8601])
    end
    db.close
  end
  def test_too_little_time_skips_paid_vision_and_ebay
    @client.failure = :weak
    result = @runner.execute('ornate-sofa', deadline: SearchDeadline.new(seconds: 9))
    assert_equal 'insufficient_time', result['status']
    assert_empty @vision.calls
    assert_equal 0, @runner.preflight[:vision_attempts]
    assert_equal %w[upload lens], @client.calls
  end
  def test_real_vision_client_calls_fake_transport_after_durable_reservation
    @client.failure = :weak
    @client.expected_query = 'carved wood curved sofa'
    runner = @runner
    transport = Object.new
    transport.define_singleton_method(:call) do |uri:, request:, deadline:, max_bytes:|
      db = runner.db
      row = runner.rows(db, EbayFlowV3::ATTEMPT_TABLE).last
      raise 'Not durably reserved before HTTP' unless row['stage'] == 'vision' && row['outcome'].nil?
      db.close
      payload = JSON.parse(request.body)
      raise 'Unexpected model or output bound' unless payload['model'] == Vision::Client::MODEL && payload['max_completion_tokens'] == 300
      raise 'Unexpected endpoint' unless uri.to_s == Vision::Client::ENDPOINT
      raise 'Image must be inline' unless payload['messages'][0]['content'][1]['image_url']['url'].start_with?('data:image/jpeg;base64,')
      body = {'model'=>Vision::Client::MODEL,'choices'=>[{'finish_reason'=>'stop','message'=>{'role'=>'assistant','content'=>JSON.generate({'status'=>'recognized','category'=>'sofa','traits'=>['carved wood','curved']})}}], 'usage'=>{'prompt_tokens'=>700,'completion_tokens'=>40,'total_tokens'=>740}}
      [200, JSON.generate(body)]
    end
    @runner.instance_variable_set(:@vision_client, Vision::Client.new(api_key: 'offline-only-key', transport: transport))
    result = @runner.execute('ornate-sofa')
    assert_equal 'success', result['status']
    assert_equal 'carved wood curved sofa', result['interpretation']
    assert_equal 740, result['query_preparation'][:metadata][:usage]['total_tokens']
    refute_match(/offline-only-key|data:image|base64/, JSON.generate(result))
  end
  def test_safe_diagnostics_exclude_message_and_arbitrary_output
    transport = EbayFlowV3::VisionDiagnosticTransport.new
    transport.instance_variable_set(:@diagnostics, {'http_status'=>400})
    transport.capture(JSON.generate({'model'=>Vision::Client::MODEL, 'choices'=>[{'finish_reason'=>'stop','message'=>{'content'=>'private'}}], 'error'=>{'type'=>'invalid_request','code'=>'unsupported_schema','message'=>'private photo or secret'}}))
    assert_equal({'http_status'=>400,'model'=>Vision::Client::MODEL,'finish_reason'=>'stop','error_type'=>'invalid_request','error_code'=>'unsupported_schema'}, transport.diagnostics)
  end
  def test_incomplete_reservation_blocks_restart
    connection = @runner.db(writable: true)
    _, sha = @runner.manifest(connection)
    connection.execute("INSERT INTO ebay_flow_v3_cases(case_id,manifest_sha256,started_at) VALUES(?,?,?)", ['ornate-sofa', sha, Time.now.utc.iso8601])
    connection.execute("INSERT INTO ebay_flow_v3_attempts(case_id,stage,manifest_sha256,parameters,reserved_at) VALUES(?,?,?,?,?)", ['ornate-sofa', 'upload', sha, '{}', Time.now.utc.iso8601])
    connection.close
    assert_raises(RuntimeError) { @runner.execute('ornate-sofa') }
    assert_raises(RuntimeError) { @runner.execute('modern-sofa') }
    assert_equal 1, @runner.preflight[:incomplete_reservations]
    assert_empty @client.calls
  end
  def test_candidate_filtering_and_order
    data = @client.ebay(params: {'engine'=>'ebay','_nkw'=>'green velvet sofa','ebay_domain'=>'ebay.com','_ipg'=>'25'}, deadline: SearchDeadline.new)
    items = data['organic_results']
    items.insert(1, items.first.dup)
    items[2]['location'] = 'Located in Canada'
    items[3]['title'] = ''
    items[4]['thumbnail'] = 'http://i.ebayimg.com/bad.jpg'
    normalized = @runner.normalize(data)
    assert_equal({'accepted'=>3, 'duplicate_item'=>1, 'not_explicit_us'=>1, 'missing_title'=>1, 'missing_thumbnail'=>1}, normalized['counts'])
    assert_equal [1,6,7], normalized['first_six'].map { |x| x['position'] }
  end
end

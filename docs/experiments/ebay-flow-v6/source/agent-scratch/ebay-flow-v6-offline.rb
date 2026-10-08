#!/usr/bin/env ruby
require_relative 'ebay-flow-v6'
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
    return {'visual_matches' => [{'title' => 'vintage sofa'}, {'title' => 'vintage couch'}]} if failure == :style
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
    @catalog = File.join(@tmp, 'catalog.json')
    @account_check = File.join(@tmp, 'account.json')
    File.write(@catalog, JSON.generate({'data'=>[{'id'=>Vision::Client::MODEL,'context_length'=>131072,'model_spec'=>{'offline'=>false,'maxCompletionTokens'=>8192,'capabilities'=>{'supportsVision'=>true,'supportsResponseSchema'=>true},'pricing'=>{'input'=>{'usd'=>0.21},'output'=>{'usd'=>1.9}}}}]}))
    @runner = EbayFlowV6::Runner.new(ledger: @ledger, directory: File.join(@tmp, 'evidence'), client: @client, vision_client: @vision, catalog_path: @catalog, account_check_path: @account_check)
    @runner.account!
    @runner.freeze!
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
  def test_lens_deadline_stops_without_retry
    @client.failure = :timeout
    result = @runner.execute('ornate-sofa')
    assert_equal 'deadline', result['status']
    assert_equal %w[upload lens], @client.calls
    assert_empty @vision.calls
    assert_raises(RuntimeError) { @runner.execute('ornate-sofa') }
    assert_equal 1, @runner.preflight[:new_searches]
  end
  def test_style_only_recognition_uses_one_reserved_vision_then_ebay
    @client.failure = :style
    @client.expected_query = 'carved wood curved sofa'
    @vision.assert_reserved = lambda do
      db = @runner.db
      row = @runner.rows(db, EbayFlowV6::ATTEMPT_TABLE).last
      assert_equal 'vision', row['stage']
      assert_nil row['outcome']
      assert_equal '0.03', JSON.parse(row['parameters'])['reserved_usd']
      db.close
    end
    result = @runner.execute('ornate-sofa')
    assert_equal 'success', result['status']
    assert_equal 'vision', result['query_source']
    assert_equal 'sofa', result['category']
    assert_equal 'sofa', result['query_preparation'][:category]
    assert_equal 'no_concrete_trait', result['query_preparation'][:metadata][:fallback_reason]
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
  def test_five_case_caps_reserve_fifteen_cents
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
    %w[upload lens ebay vision].each do |stage|
      assert_raises(SQLite3::ConstraintException) do
        db.execute("INSERT INTO #{EbayFlowV6::ATTEMPT_TABLE}(case_id,stage,manifest_sha256,parameters,reserved_at) VALUES(?,?,?,?,?)", ['extra', stage, sha, '{}', Time.now.utc.iso8601])
      end
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
      row = runner.rows(db, EbayFlowV6::ATTEMPT_TABLE).last
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
    transport = EbayFlowV6::VisionDiagnosticTransport.new
    transport.instance_variable_set(:@diagnostics, {'http_status'=>400})
    transport.capture(JSON.generate({'model'=>Vision::Client::MODEL, 'choices'=>[{'finish_reason'=>'stop','message'=>{'content'=>'private'}}], 'error'=>{'type'=>'invalid_request','code'=>'unsupported_schema','message'=>'private photo or secret'}}))
    assert_equal({'http_status'=>400,'model'=>Vision::Client::MODEL,'finish_reason'=>'stop','error_type'=>'invalid_request','error_code'=>'unsupported_schema'}, transport.diagnostics)
  end
  def test_incomplete_reservation_blocks_restart
    connection = @runner.db(writable: true)
    _, sha = @runner.manifest(connection)
    connection.execute("INSERT INTO ebay_flow_v6_cases(case_id,manifest_sha256,started_at) VALUES(?,?,?)", ['ornate-sofa', sha, Time.now.utc.iso8601])
    connection.execute("INSERT INTO ebay_flow_v6_attempts(case_id,stage,manifest_sha256,parameters,reserved_at) VALUES(?,?,?,?,?)", ['ornate-sofa', 'upload', sha, '{}', Time.now.utc.iso8601])
    connection.close
    assert_raises(RuntimeError) { @runner.execute('ornate-sofa') }
    assert_raises(RuntimeError) { @runner.execute('modern-sofa') }
    assert_equal 1, @runner.preflight[:incomplete_reservations]
    assert_empty @client.calls
  end
  def test_title_filter_precedes_first_six_and_preserves_order
    data = @client.ebay(params: {'engine'=>'ebay','_nkw'=>'green velvet sofa','ebay_domain'=>'ebay.com','_ipg'=>'25'}, deadline: SearchDeadline.new)
    good = data['organic_results']
    wrong = ['Sofa side table', 'Vintage rug', 'Replacement sofa legs'].each_with_index.map do |title, i|
      good.first.merge('title'=>title, 'link'=>"https://www.ebay.com/itm/#{9000+i}", 'sponsored'=>true)
    end
    data['organic_results'] = wrong + good
    normalized = @runner.normalize(data, category: 'sofa')
    assert_equal 9, normalized['eligible_before_title_filter'].size
    assert_equal 6, normalized['candidates'].size
    assert_equal (4..9).to_a, normalized['first_six'].map { |row| row['position'] }
    assert_equal({'mixed_categories'=>1, 'different_item'=>1, 'accessory_or_part'=>1, 'accepted'=>6}, normalized['title_filter_counts'])
    assert_equal 'sofa', normalized['category']
  end
  def test_history_counts_exclude_vision
    pre = @runner.preflight
    assert_equal 48, pre[:historical_searches]
    assert_equal 7, pre[:historical_vision_attempts]
    assert_equal %w[ornate-sofa modern-sofa dining-chair wood-table dresser], pre[:cases]
    assert_equal 25, EbayFlowV6::TABLES.size
  end
  def test_two_failures_stop_later_cases_without_dispatch
    %w[ornate-sofa modern-sofa].each do |id|
      result = @runner.execute(id)
      refute score(id, result, good: false)['passed']
    end
    before = @client.calls.dup
    assert_raises(RuntimeError) { @runner.execute('dining-chair') }
    assert_equal before, @client.calls
    assert_equal 2, @runner.preflight[:failed_cases]
    db = @runner.db(writable: true)
    _, sha = @runner.manifest(db)
    assert_raises(SQLite3::ConstraintException) do
      db.execute("INSERT INTO #{EbayFlowV6::CASE_TABLE}(case_id,manifest_sha256,started_at) VALUES(?,?,?)", ['dining-chair', sha, Time.now.utc.iso8601])
    end
    db.close
  end
  def test_each_case_requires_manual_score_before_next
    result = @runner.execute('ornate-sofa')
    before = @client.calls.dup
    assert_raises(RuntimeError) { @runner.execute('modern-sofa') }
    assert_equal before, @client.calls
    score('ornate-sofa', result)
    assert_equal 'success', @runner.execute('modern-sofa')['status']
  end
  def test_freeze_requires_recent_account_and_preserves_deployment_reserve
    dir = File.join(@tmp, 'second-evidence')
    runner = EbayFlowV6::Runner.new(ledger: @ledger, directory: dir, client: @client, vision_client: @vision, catalog_path: @catalog, account_check_path: File.join(@tmp, 'absent-account.json'))
    assert_raises(RuntimeError) { runner.verified_pre_freeze_account(runner.db) }
    account = JSON.parse(File.read(@account_check))
    account['summary']['total_searches_left'] = 11
    File.write(@account_check, JSON.generate(account))
    assert_raises(RuntimeError) { @runner.verified_pre_freeze_account(@runner.db) }
    account['summary']['total_searches_left'] = 12
    File.write(@account_check, JSON.generate(account))
    assert_equal 12, @runner.verified_pre_freeze_account(@runner.db)['summary']['total_searches_left']
    account['checked_at'] = (Time.now.utc - 3601).iso8601
    File.write(@account_check, JSON.generate(account))
    assert_raises(RuntimeError) { @runner.verified_pre_freeze_account(@runner.db) }
  end
  def test_freeze_records_auditable_source_copies_and_git_baseline
    db = @runner.db
    manifest, = @runner.manifest(db)
    assert_match(/\A[0-9a-f]{40}\z/, manifest['git_head_at_freeze'])
    assert_equal EbayFlowV6::SOURCES.sort, manifest['source_snapshots'].keys.sort
    copy = manifest['source_snapshots'].fetch('app/services/serp_api/client.rb')
    assert_equal EbayFlowV6.digest(Rails.root.join('app/services/serp_api/client.rb')), copy.fetch('sha256')
    assert_equal 25, manifest['prior_tables'].size
    assert_equal 'ebay-title-filter-v2', manifest['listing_filter_version']
    assert_equal 'furniture-photo-v2', manifest.dig('vision_policy', 'prompt_version')
    assert_equal 10, manifest.dig('budget','searches')
    assert_equal 0.15, manifest.dig('budget','vision_reserved_usd_total')
    assert_equal 2, manifest.dig('budget','separate_deployment_search_reserve')
    db.close
  end
  def test_candidate_filtering_and_order
    data = @client.ebay(params: {'engine'=>'ebay','_nkw'=>'green velvet sofa','ebay_domain'=>'ebay.com','_ipg'=>'25'}, deadline: SearchDeadline.new)
    items = data['organic_results']
    items.insert(1, items.first.dup)
    items[2]['location'] = 'Located in Canada'
    items[3]['title'] = ''
    items[4]['thumbnail'] = 'http://i.ebayimg.com/bad.jpg'
    normalized = @runner.normalize(data, category: 'sofa')
    assert_equal({'accepted'=>3, 'duplicate_item'=>1, 'not_explicit_us'=>1, 'missing_title'=>1, 'missing_thumbnail'=>1}, normalized['counts_before_title_filter'])
    assert_equal [1,6,7], normalized['first_six'].map { |x| x['position'] }
  end
end

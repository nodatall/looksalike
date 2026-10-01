#!/usr/bin/env ruby
require_relative 'ebay-flow-v2'
require 'tmpdir'
require 'minitest/autorun'

# This executable cannot issue requests, even if injection is accidentally bypassed.
class SerpApi::HttpTransport
  def call(**) = raise('LIVE NETWORK FORBIDDEN IN OFFLINE CHECKS')
end

class FlowFakeClient
  attr_reader :calls
  attr_accessor :failure
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
    raise 'Unwanted request filter' unless params == {'engine' => 'ebay', '_nkw' => 'green velvet sofa', 'ebay_domain' => 'ebay.com', '_ipg' => '25'}
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
    @runner = EbayFlowV2::Runner.new(ledger: @ledger, directory: File.join(@tmp, 'evidence'), client: @client)
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
  def test_weak_recognition_skips_ebay_and_counts_only_lens
    @client.failure = :weak
    result = @runner.execute('ornate-sofa')
    assert_equal 'weak_recognition', result['status']
    assert_equal %w[upload lens], @client.calls
    assert_equal 1, @runner.preflight[:new_searches]
    refute score('ornate-sofa', result)['passed']
  end
  def test_incomplete_reservation_blocks_restart
    connection = @runner.db(writable: true)
    _, sha = @runner.manifest(connection)
    connection.execute("INSERT INTO ebay_flow_v2_cases(case_id,manifest_sha256,started_at) VALUES(?,?,?)", ['ornate-sofa', sha, Time.now.utc.iso8601])
    connection.execute("INSERT INTO ebay_flow_v2_attempts(case_id,stage,manifest_sha256,parameters,reserved_at) VALUES(?,?,?,?,?)", ['ornate-sofa', 'upload', sha, '{}', Time.now.utc.iso8601])
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

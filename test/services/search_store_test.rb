require "test_helper"
require "active_support/testing/constant_stubbing"

class SearchStoreTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing
  self.use_transactional_tests = false

  def setup
    SearchCacheEntry.delete_all
    SearchUsageReservation.delete_all
    SearchLease.delete_all
    SearchLease.create!(id: 1)
    @now = Time.utc(2026, 9, 29, 12)
    @store = store
  end

  def teardown
    SearchCacheEntry.delete_all
    SearchUsageReservation.delete_all
    SearchLease.delete_all
    SearchLease.create!(id: 1)
    super
  end

  def store(**limits)
    env = limits.transform_keys { |key| SearchSettings::LIMITS.fetch(key).first }.transform_values(&:to_s)
    SearchStore.new(settings: SearchSettings.new(env: env), now: -> { @now })
  end

  def acquire(store = @store, key: "photo", session: "visitor", ip: "127.0.0.1")
    store.acquire(key: key, session_id: session, ip: ip)
  end

  def completed(status = "success")
    { "version" => EbaySearch::VERSION, "status" => status, "source" => "live", "retrieved_at" => @now.iso8601,
      "attempts" => { "uploads" => 1, "serpapi" => 2, "vision" => 0 },
      "original_attempts" => { "uploads" => 1, "serpapi" => 2, "vision" => 0 }, "listings" => [], "stages" => [] }
  end

  test "cache hits preserve retrieval and original calls without allowance or lease and expire independently" do
    token = acquire.token
    @store.finish(token: token, key: "photo", result: completed)
    @now += 23.hours
    fresh_store = store
    cached = acquire(fresh_store)
    assert_equal "cache", cached.status
    assert_equal "cache", cached.cached_result["source"]
    assert_equal({ "uploads" => 0, "serpapi" => 0, "vision" => 0 }, cached.cached_result["attempts"])
    assert_equal 2, cached.cached_result["original_attempts"]["serpapi"]
    assert_equal Time.utc(2026, 9, 29, 12).iso8601, cached.cached_result["retrieved_at"]
    assert_equal 1, SearchUsageReservation.count
    @now += 1.hour
    assert_nil fresh_store.lookup("photo")
    token = acquire(fresh_store, key: "empty").token
    fresh_store.finish(token: token, key: "empty", result: completed("empty"))
    @now += 1.hour
    assert_nil fresh_store.lookup("empty")
    assert_not_equal SearchStore.cache_key("photo1"), SearchStore.cache_key("photo2")
    original = SearchStore.cache_key("photo1")
    stub_const(EbayListingNormalizer, :VERSION, "ebay-listings-v1") { assert_not_equal original, SearchStore.cache_key("photo1") }
    stub_const(EbayListingFilter, :VERSION, "test-next-filter") { assert_not_equal original, SearchStore.cache_key("photo1") }
    stub_const(Vision::Client, :PROMPT_VERSION, "test-next-prompt") { assert_not_equal original, SearchStore.cache_key("photo1") }
  end

  test "busy and expired leases survive store recreation and stale owners cannot unlock replacements" do
    first = acquire
    assert_equal "live", first.status
    assert_equal "busy", acquire(store, key: "different").status
    assert_equal 1, SearchUsageReservation.count
    @now += SearchStore::LEASE_SECONDS + 1
    second = acquire(store, key: "different")
    assert_equal "live", second.status
    @store.release(first.token)
    assert_equal second.token, SearchLease.find(1).owner_token
    assert_raises(SearchStore::Error) { @store.finish(token: first.token, key: "photo", result: completed) }
    assert_equal 4, SearchUsageReservation.sum(:units)
    @store.release(second.token)
    assert_nil SearchLease.find(1).owner_token
  end

  test "simultaneous different photos cannot reserve past the shared ceiling" do
    barrier = Queue.new
    racers = 2.times.map do |index|
      Thread.new do
        barrier.pop
        value = acquire(store(daily: 2), key: "photo#{index}", session: "visitor#{index}", ip: "127.0.0.#{index + 1}")
        @store.release(value.token) if value.token
        value.status
      end
    end
    2.times { barrier << true }
    statuses = racers.map(&:value)
    assert_equal 1, statuses.count("live")
    assert_equal 2, SearchUsageReservation.where(kind: "serpapi").sum(:units)
    assert_equal 1, SearchUsageReservation.count
  end

  test "session and IP each cap fresh requests and failures are not refunded or cached" do
    token = acquire(store(visitor: 1)).token
    @store.finish(token: token, key: "photo", result: completed("provider_unavailable"))
    assert_nil @store.lookup("photo")
    assert_equal "visitor_limit", acquire(store(visitor: 1), key: "other", session: "another").status
    assert_equal "visitor_limit", acquire(store(visitor: 1), key: "other", ip: "127.0.0.2").status
    row = SearchUsageReservation.first
    refute_equal "visitor", row.session_digest
    refute_equal "127.0.0.1", row.ip_digest
    assert_equal 64, row.ip_digest.length
    @now += 1.hour + 1
    assert_equal "live", acquire(store(visitor: 1), key: "other").status
  end

  test "rolling and daily vision caps reserve once at three cents and never refund" do
    constrained = store(vision_daily: 1, vision_rolling: 1, rolling: 4)
    first = acquire(constrained)
    assert constrained.reserve_vision(first.token)
    refute constrained.reserve_vision(first.token)
    constrained.release(first.token)
    @now += 1.day
    second = acquire(constrained, key: "other")
    refute constrained.reserve_vision(second.token)
    constrained.release(second.token)
    assert_equal 3, SearchUsageReservation.where(kind: "vision").sum(:reserved_cents)
    assert_equal "quota_exceeded", acquire(constrained, key: "third").status
    @now += 30.days
    third = acquire(constrained, key: "third")
    assert constrained.reserve_vision(third.token)
  end

  test "bad config or missing persistent lease fails closed" do
    [ { "SEARCH_DAILY_ATTEMPT_LIMIT" => "0" }, { "SEARCH_DAILY_ATTEMPT_LIMIT" => "11" },
      { "SEARCH_DEADLINE_SECONDS" => "56" }, { "LIVE_SEARCH_ENABLED" => "perhaps" } ].each do |env|
      assert_raises(SearchSettings::Invalid) { SearchSettings.new(env: env) }
    end
    SearchLease.delete_all
    assert_raises(SearchStore::Error) { acquire }
    assert_equal 0, SearchUsageReservation.count
  end
end

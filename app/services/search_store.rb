require "digest"
require "json"
require "openssl"
require "securerandom"

class SearchStore
  LEASE_SECONDS = 75
  Grant = Data.define(:status, :token, :cached_result)
  class Error < StandardError; end

  def initialize(settings: SearchSettings.new, now: -> { Time.now.utc })
    @limits = settings.limits
    @now = now
  end

  def self.cache_key(photo_sha256)
    versions = [ "ebay-us-v1", photo_sha256, "ebay.com", EbayListingNormalizer::US_RULE,
      EbayListingNormalizer::VERSION, EbayListingFilter::VERSION, SearchQuery::VERSION,
      PhotoQuery::TRIGGER_VERSION, PhotoQuery::VERSION, Vision::Client.metadata.except(:reserved_usd) ]
    Digest::SHA256.hexdigest(JSON.generate(versions))
  end

  def lookup(key)
    with_database { cached(key, @now.call) }
  end

  # SQLite's short BEGIN IMMEDIATE transaction serializes lease and quota decisions.
  # No HTTP or photo processing occurs while a connection is held here.
  def acquire(key:, session_id:, ip:)
    session_digest = visitor_digest("session", session_id)
    ip_digest = visitor_digest("ip", ip)
    with_database do
      ApplicationRecord.transaction do
        lease = lock_lease
        now = @now.call
        if (result = cached(key, now))
          Grant.new(status: "cache", token: nil, cached_result: result)
        elsif lease.owner_token && lease.expires_at && lease.expires_at > now
          Grant.new(status: "busy", token: nil, cached_result: nil)
        elsif usage("serpapi", now.beginning_of_day) + 2 > @limits.fetch(:daily) || usage("serpapi", now - 30.days) + 2 > @limits.fetch(:rolling)
          Grant.new(status: "quota_exceeded", token: nil, cached_result: nil)
        else
          token = SecureRandom.uuid
          SearchUsageReservation.create!(owner_token: token, kind: "serpapi", units: 2,
            session_digest: session_digest, ip_digest: ip_digest, created_at: now)
          lease.update!(owner_token: token, expires_at: now + LEASE_SECONDS)
          Grant.new(status: "live", token: token, cached_result: nil)
        end
      end
    end
  end

  def reserve_vision(token)
    with_database do
      ApplicationRecord.transaction do
        lease = lock_lease
        now = @now.call
        raise Error unless owned?(lease, token, now)
        return false if usage("vision", now.beginning_of_day) + 1 > @limits.fetch(:vision_daily) || usage("vision", now - 30.days) + 1 > @limits.fetch(:vision_rolling)
        return false if SearchUsageReservation.exists?(owner_token: token, kind: "vision")
        SearchUsageReservation.create!(owner_token: token, kind: "vision", units: 1, reserved_cents: 3, created_at: now)
        true
      end
    end
  end

  def finish(token:, key:, result:)
    with_database do
      ApplicationRecord.transaction do
        lease = lock_lease
        now = @now.call
        raise Error unless owned?(lease, token, now)
        if %w[success empty].include?(result.fetch("status"))
          entry = SearchCacheEntry.find_or_initialize_by(fingerprint: key)
          entry.update!(payload: JSON.generate(result), expires_at: now + 1.hour)
        end
        lease.update!(owner_token: nil, expires_at: nil)
      end
    end
  end

  def release(token)
    return unless token
    with_database { SearchLease.where(id: 1, owner_token: token).update_all(owner_token: nil, expires_at: nil) }
  end

  private
    def with_database
      if Rails.env.production?
        ProductionStorage.validate!(config: ApplicationRecord.connection_db_config)
      end
      pool = ApplicationRecord.connection_pool
      pool.with_connection do |connection|
        raise Error unless connection.adapter_name == "SQLite"
        yield
      end
    rescue ProductionStorage::Unavailable, ActiveRecord::ActiveRecordError, JSON::ParserError, KeyError, TypeError, ArgumentError
      raise Error, cause: nil
    end

    def lock_lease
      # Force the write transaction before reading caps, even for a busy response.
      raise Error unless SearchLease.where(id: 1).update_all("id = id") == 1
      SearchLease.find(1)
    end

    def owned?(lease, token, now)
      token && lease.owner_token == token && lease.expires_at && lease.expires_at > now
    end

    def usage(kind, since)
      SearchUsageReservation.where(kind: kind).where("created_at >= ?", since).sum(:units)
    end

    def visitor_digest(kind, value)
      raise Error unless value.is_a?(String) && value.bytesize.between?(1, 512)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "search-#{kind}:#{value}")
    end

    def cached(key, now)
      entry = SearchCacheEntry.find_by(fingerprint: key)
      return unless entry && entry.expires_at > now
      result = JSON.parse(entry.payload)
      raise Error unless result.is_a?(Hash) && result["version"] == "ebay-us-v1" && %w[success empty].include?(result["status"])
      # Enforce the shorter policy for entries written with the former 24-hour TTL.
      return if Time.iso8601(result.fetch("retrieved_at")) <= now - 1.hour
      result.merge("source" => "cache", "attempts" => { "uploads" => 0, "serpapi" => 0, "vision" => 0 })
    end
end

#!/usr/bin/env ruby
# One-off approved diagnostic. Default is read-only; root owns live execution.
abort "Use local development without DATABASE_URL" if ENV["DATABASE_URL"] || (ENV["RAILS_ENV"] && ENV["RAILS_ENV"] != "development")
ENV["RAILS_ENV"] = "development"
require_relative "../config/environment"
abort "Remove DATABASE_URL from local dotenv configuration" if ENV["DATABASE_URL"]
require "sqlite3"
require "net/http"
require "digest"
require "json"
require "time"
require "fileutils"

module DiagnosticV1
  extend self
  class Failure < StandardError
    attr_reader :code, :http_status
    def initialize(code, http_status = nil)
      @code, @http_status = code, http_status
      super(code)
    end
  end
  MAX_BYTES = 2_000_000
  EMPTY_ERROR = "Google hasn't returned any results for this query.".freeze
  CASES = {
    "ornate-sofa" => { "engine" => "google_images", "q" => "sofa antique photos download free settees vintage site:newyork.craigslist.org", "location" => "New York,New York,United States", "gl" => "us", "hl" => "en" }.freeze,
    "modern-sofa" => { "engine" => "google_images", "q" => "sofa green velvet seater site:sfbay.craigslist.org", "location" => "San Francisco,California,United States", "gl" => "us", "hl" => "en" }.freeze
  }.freeze

  def params_hash(id)
    Digest::SHA256.hexdigest(JSON.generate(CASES.fetch(id)))
  end

  def table?(db)
    !!db.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'diagnostic_v1_attempts'")
  end

  def rows(db)
    table?(db) ? db.execute("SELECT * FROM diagnostic_v1_attempts ORDER BY reserved_at, case_id") : []
  end

  def original!(db, checksum)
    identity = db.get_first_row("SELECT * FROM identity WHERE id = 1")
    raise Failure.new("manifest_identity_mismatch") unless identity && identity["manifest"] == checksum
    raise Failure.new("original_budget_mismatch") unless db.get_first_value("SELECT COUNT(*) FROM attempts WHERE stage != 'upload'") == 6 && db.get_first_value("SELECT COUNT(*) FROM attempts WHERE stage = 'upload'") == 4
  end

  def known_evidence!(db, evidence_path)
    return unless File.exist?(evidence_path)
    raise Failure.new("diagnostic_evidence_without_ledger") unless table?(db) && File.size(evidence_path) <= 100_000
    saved = JSON.parse(File.read(evidence_path))
    known = rows(db).to_h { |row| [ row.fetch("case_id"), row ] }
    raise Failure.new("diagnostic_evidence_without_reservations") unless saved.fetch("attempts").is_a?(Array) && saved.fetch("attempts").any?
    saved.fetch("attempts").each do |attempt|
      row = known[attempt.fetch("case_id")]
      raise Failure.new("diagnostic_evidence_without_reservations") unless row && row["params_sha256"] == attempt["params_sha256"] && row["reserved_at"] == attempt["reserved_at"]
    end
  rescue JSON::ParserError, KeyError
    raise Failure.new("invalid_diagnostic_evidence")
  end

  def allowance!(db, diagnostic_count, now = Time.now.utc)
    account = db.get_first_row("SELECT checked_at, searches_left, attempts_at_check FROM account_checks ORDER BY id DESC LIMIT 1")
    raise Failure.new("account_check_missing_or_stale") unless account && (now - Time.iso8601(account["checked_at"])).between?(0, 3600)
    baseline = account["attempts_at_check"]
    left = account["searches_left"]
    raise Failure.new("invalid_account_allowance") unless baseline.is_a?(Integer) && baseline.between?(0, 6) && left.is_a?(Integer)
    raise Failure.new("account_allowance_insufficient") unless left - (6 - baseline) - diagnostic_count >= 1
    true
  end

  def open_db(root, writable: false)
    path = root.join("storage/feasibility-v1.sqlite3")
    raise Failure.new("missing_or_unexpected_ledger_path") unless path.file? && !path.symlink? && path.dirname.realpath == path.dirname
    db = SQLite3::Database.new(path.to_s, flags: writable ? SQLite3::Constants::Open::READWRITE : SQLite3::Constants::Open::READONLY)
    db.results_as_hash = true
    db.busy_timeout = 5000
    db.execute("PRAGMA synchronous = FULL") if writable
    db
  end

  def preflight(root: Rails.root, deadline: SearchDeadline.new)
    root = Pathname(root).realpath
    manifest = ExperimentManifest.new(root: root).verify!(deadline: deadline)
    original = JSON.parse(File.read(root.join("docs/experiments/feasibility-v1/live-evidence.json")))
    raise Failure.new("original_evidence_mismatch") unless original["manifest_sha256"] == manifest.checksum && original["search_attempts"] == 6 && original["upload_attempts"] == 4
    CASES.each do |id, params|
      entry = original.fetch("routes").fetch("lens_then_images").fetch("cases").find { |item| item["case_id"] == id }
      observed = entry.fetch("outcome").fetch("parameters").find { |item| item["engine"] == "google_images" }
      raise Failure.new("request_parameters_changed") unless params == observed
    end
    db = open_db(root)
    original!(db, manifest.checksum)
    known_evidence!(db, root.join("docs/experiments/diagnostic-v1/results.json"))
    existing = rows(db)
    raise Failure.new("diagnostic_budget_invalid") unless existing.length <= 2 && existing.all? { |row| CASES.key?(row["case_id"]) && row["params_sha256"] == params_hash(row["case_id"]) }
    allowance = begin
      allowance!(db, existing.length)
      "ready"
    rescue Failure => error
      error.code
    end
    deadline.remaining
    { "status" => "offline_preflight_passed", "manifest_sha256" => manifest.checksum, "original_search_attempts" => 6,
      "original_upload_attempts" => 4, "diagnostic_attempts" => existing.length, "combined_search_attempts" => 6 + existing.length,
      "combined_ceiling" => 8, "allowance" => allowance, "requests" => CASES, "attempts" => safe_rows(existing) }
  ensure
    db&.close
  end

  def reserve!(db, id, checksum:, evidence_path:)
    raise Failure.new("unapproved_case") unless CASES.key?(id)
    db.transaction(:immediate) do
      original!(db, checksum)
      known_evidence!(db, evidence_path)
      existing = rows(db)
      raise Failure.new("duplicate_or_exhausted_diagnostic") if existing.any? { |row| row["case_id"] == id } || existing.length >= 2 || 6 + existing.length >= 8
      allowance!(db, existing.length)
      db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS diagnostic_v1_attempts (
          case_id TEXT PRIMARY KEY CHECK(case_id IN ('ornate-sofa', 'modern-sofa')),
          params_sha256 TEXT NOT NULL, reserved_at TEXT NOT NULL,
          observed_at TEXT, outcome TEXT
        );
        CREATE TRIGGER IF NOT EXISTS diagnostic_v1_no_delete BEFORE DELETE ON diagnostic_v1_attempts BEGIN SELECT RAISE(ABORT, 'Immutable attempt'); END;
        CREATE TRIGGER IF NOT EXISTS diagnostic_v1_identity BEFORE UPDATE OF case_id, params_sha256, reserved_at ON diagnostic_v1_attempts BEGIN SELECT RAISE(ABORT, 'Immutable attempt'); END;
        CREATE TRIGGER IF NOT EXISTS diagnostic_v1_once BEFORE UPDATE OF outcome, observed_at ON diagnostic_v1_attempts WHEN OLD.outcome IS NOT NULL BEGIN SELECT RAISE(ABORT, 'Outcome already recorded'); END;
        CREATE TRIGGER IF NOT EXISTS diagnostic_v1_cap BEFORE INSERT ON diagnostic_v1_attempts WHEN (SELECT COUNT(*) FROM diagnostic_v1_attempts) >= 2 BEGIN SELECT RAISE(ABORT, 'Diagnostic cap'); END;
      SQL
      db.execute("INSERT INTO diagnostic_v1_attempts(case_id, params_sha256, reserved_at) VALUES (?, ?, ?)", [ id, params_hash(id), Time.now.utc.iso8601(6) ])
    end
  end

  def fetch(params, deadline)
    deadline.within do
      uri = URI("https://serpapi.com/search.json")
      # Credentials are accessed only here, for this explicit request, never exported.
      key = ENV.fetch("SERPAPI_API_KEY")
      raise Failure.new("missing_key") if key.empty?
      uri.query = URI.encode_www_form(params.merge("api_key" => key))
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["Accept-Encoding"] = "identity"
      http = Net::HTTP.new("serpapi.com", 443, nil)
      http.use_ssl = true
      http.max_retries = 0
      http.open_timeout = http.read_timeout = http.write_timeout = deadline.remaining
      status = nil
      body = +"".b
      http.start do |connection|
        connection.request(request) do |response|
          status = response.code.to_i
          length = response["Content-Length"]
          raise Failure.new("response_too_large", status) if length && length.to_i > MAX_BYTES
          response.read_body do |chunk|
            deadline.remaining
            raise Failure.new("response_too_large", status) if body.bytesize + chunk.bytesize > MAX_BYTES
            body << chunk
            http.read_timeout = deadline.remaining
          end
        end
      end
      [ status, body, ->(value) { value.gsub(/#{Regexp.escape(key)}/i, "[redacted]") } ]
    end
  end

  def path_shape(uri)
    return "unparseable" unless uri
    parts = uri.path.to_s.split("/").reject(&:empty?).first(12).map do |part|
      if %w[search view d].include?(part) then part
      elsif part.match?(/\A[0-9]+\.html\z/) then "<id>.html"
      elsif part.end_with?(".html") then "<segment>.html"
      elsif part.match?(/\A[0-9]+\z/) then "<number>"
      else "<segment>"
      end
    end
    "/#{parts.join('/')}"[0, 100]
  end

  def url_summary(items, normalizer, hostname, redact)
    reasons = Hash.new(0)
    hosts = Hash.new(0)
    shapes = Hash.new(0)
    examples = []
    items.each do |item|
      link = item.is_a?(Hash) ? item["link"] : nil
      uri = normalizer.send(:safe_uri, link)
      reason = if !uri then "invalid_url"
      elsif uri.host.downcase != hostname then "wrong_hostname"
      elsif !ListingNormalizer::LISTING_PATH.match?(uri.path) then "selected_host_invalid_individual_path"
      else "accepted_url"
      end
      reasons[reason] += 1
      parsed = begin
        link.is_a?(String) && link.bytesize <= 2048 ? URI.parse(link) : nil
      rescue URI::InvalidURIError, ArgumentError
        nil
      end
      host = redact.call(parsed&.host.to_s.downcase)
      host = "unparseable_host" unless host.match?(/\A[a-z0-9.-]{1,150}\z/)
      host = "other_hosts" unless hosts.key?(host) || hosts.length < 50
      shape = path_shape(parsed)
      hosts[host] += 1
      shapes[shape] += 1
      example = "#{reason}: #{host}#{shape}"[0, 200]
      examples << example if examples.length < 10 && !examples.include?(example)
    end
    { "url_reasons" => reasons, "destination_hosts" => hosts, "path_shapes" => shapes, "examples" => examples }
  end

  def classify(status, body, id, redact: ->(value) { value })
    base = { "http_status" => status, "provider_status" => nil, "error_present" => nil }
    return base.merge("classification" => "response_too_large") unless body.is_a?(String) && body.bytesize <= MAX_BYTES
    data = JSON.parse(body)
    return base.merge("classification" => "invalid_json_shape") unless data.is_a?(Hash)
    metadata = data["search_metadata"]
    provider_status = metadata.is_a?(Hash) ? metadata["status"] : nil
    base["provider_status"] = provider_status if %w[Success Error Processing Queued].include?(provider_status)
    base["error_present"] = data.key?("error")
    empty = data["error"] == EMPTY_ERROR
    base["documented_empty_error"] = EMPTY_ERROR if empty
    base["classification"] = if status != 200 then "http_error"
    elsif empty && provider_status == "Success" then "empty_results"
    elsif data.key?("error") then "provider_error"
    elsif provider_status != "Success" then "unexpected_provider_status"
    elsif !data["images_results"].is_a?(Array) || data["images_results"].empty? then "no_image_results"
    else "results_returned"
    end
    items = data["images_results"].is_a?(Array) ? data["images_results"] : []
    zip = id == "ornate-sofa" ? "10001" : "94103"
    location = LocationResolver.resolve(zip)
    normalizer = ListingNormalizer.new(approved_hostnames: LocationResolver::CATALOG.fetch("areas").map { |area| area.fetch("hostname") })
    normalized = normalizer.call(items, location: location, route: "lens_then_images", query: CASES.fetch(id).fetch("q").sub(/ site:[^\s]+\z/, ""))
    base.merge("normalizer_counts" => normalized.counts, **url_summary(items, normalizer, location.hostname, redact))
  rescue JSON::ParserError
    base.merge("classification" => "invalid_json")
  end

  def safe_rows(records)
    records.map do |row|
      { "case_id" => row.fetch("case_id"), "params_sha256" => row.fetch("params_sha256"), "reserved_at" => row.fetch("reserved_at"),
        "parameters" => CASES.fetch(row.fetch("case_id")), "observed_at" => row["observed_at"],
        "outcome" => row["outcome"] ? JSON.parse(row["outcome"]) : { "classification" => "reserved_dispatch_uncertain" } }
    end
  end

  def observe!(db, id, checksum:, evidence_path:, deadline:, transport: method(:fetch))
    deadline.remaining
    reserve!(db, id, checksum: checksum, evidence_path: evidence_path)
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = begin
      deadline.within do
        status, body, redact = begin
          transport.call(CASES.fetch(id), deadline)
        rescue SearchDeadline::Exceeded, Failure
          raise
        rescue StandardError
          raise Failure.new("transport_error"), cause: nil
        end
        classify(status, body, id, redact: redact || ->(value) { value })
      end
    rescue SearchDeadline::Exceeded
      { "classification" => "deadline" }
    rescue Failure => error
      { "classification" => error.code, "http_status" => error.http_status }
    rescue StandardError
      { "classification" => "probe_processing_error" }
    end
    result["elapsed_ms"] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - began) * 1000).round(3)
    db.transaction(:immediate) do
      db.execute("UPDATE diagnostic_v1_attempts SET observed_at = ?, outcome = ? WHERE case_id = ? AND outcome IS NULL", [ Time.now.utc.iso8601(6), JSON.generate(result), id ])
      raise Failure.new("outcome_already_recorded") unless db.changes == 1
    end
    result
  end

  def execute(id, root: Rails.root)
    raise Failure.new("unapproved_case") unless CASES.key?(id)
    deadline = SearchDeadline.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pre = preflight(root: root, deadline: deadline)
    root = Pathname(root).realpath
    db = open_db(root, writable: true)
    evidence_path = root.join("docs/experiments/diagnostic-v1/results.json")
    observe!(db, id, checksum: pre.fetch("manifest_sha256"), evidence_path: evidence_path, deadline: deadline)
    records = rows(db)
    report = { "diagnostic" => "diagnostic-v1", "manifest_sha256" => pre.fetch("manifest_sha256"), "probe_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
      "original_search_attempts" => 6, "diagnostic_attempts" => records.length, "combined_search_attempts" => 6 + records.length, "combined_ceiling" => 8,
      "comparison_ceiling" => 15, "final_smoke_attempts_used" => 0, "execution_elapsed_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3),
      "meaning" => "Current observations only; original v1 scores and historical failure causes are unchanged. Reservations count even on errors or cache hits.", "attempts" => safe_rows(records) }
    payload = JSON.pretty_generate(report) + "\n"
    raise Failure.new("evidence_too_large") if payload.bytesize > 100_000
    FileUtils.mkdir_p(evidence_path.dirname)
    temp = "#{evidence_path}.tmp-#{Process.pid}"
    File.write(temp, payload, mode: "wx", perm: 0o600)
    File.rename(temp, evidence_path)
    report
  ensure
    db&.close
    File.delete(temp) if temp && File.exist?(temp)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    result = if ARGV.empty?
      DiagnosticV1.preflight
    elsif ARGV.length == 2 && ARGV.first == "--execute"
      DiagnosticV1.execute(ARGV.last)
    else
      raise DiagnosticV1::Failure.new("usage_default_or_execute_approved_case")
    end
    puts JSON.pretty_generate(result)
  rescue DiagnosticV1::Failure => error
    warn "Diagnostic stopped: #{error.code}. Reserved attempts remain spent."
    exit 1
  rescue StandardError
    warn "Diagnostic stopped safely. Inspect existing reservations; do not retry an uncertain case."
    exit 1
  end
end

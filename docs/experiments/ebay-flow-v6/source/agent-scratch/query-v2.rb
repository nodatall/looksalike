#!/usr/bin/env ruby
# One-off replay; importing the old helper does not execute its CLI.
require_relative "diagnostic-v1"

module QueryV2
  extend self
  Failure = DiagnosticV1::Failure
  ORDER = %w[modern-sofa ornate-sofa].freeze
  DIRECTORY = "docs/experiments/query-v2".freeze
  OLD_DIRECTORY = "docs/experiments/feasibility-v1".freeze
  NEW_QUERY = "app/models/search_query.rb".freeze
  ARCHIVE = "#{DIRECTORY}/search_query_v1.rb".freeze
  NO_RESULTS = /\AGoogle(?: Images)? (?:hasn't|has not) returned any results for this (?:query|search)\.?\z/.freeze

  def digest(path)
    Digest::SHA256.file(path).hexdigest
  end

  def encoded_hash(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end

  def historical!(root)
    old_path = root.join(OLD_DIRECTORY, "manifest.json")
    old = JSON.parse(File.read(old_path))
    raise Failure.new("historical_manifest_changed") unless digest(old_path) == File.read(root.join(OLD_DIRECTORY, "manifest.sha256")).strip
    old.fetch("artifacts").each do |name, expected|
      actual = root.join(name == NEW_QUERY ? ARCHIVE : name)
      raise Failure.new("historical_artifact_changed") unless actual.file? && actual.size == expected.fetch("bytes") && digest(actual) == expected.fetch("sha256")
    end
    old
  end

  def expected_cases(root)
    evidence = JSON.parse(File.read(root.join(OLD_DIRECTORY, "live-evidence.json")))
    ORDER.map do |id|
      saved = evidence.fetch("routes").fetch("lens_then_images").fetch("cases").find { |item| item["case_id"] == id }
      params = saved.fetch("outcome").fetch("parameters").find { |item| item["engine"] == "google_images" }
      raise Failure.new("original_parameters_changed") unless params == DiagnosticV1::CASES.fetch(id)
      phrase = params.fetch("q").sub(/ site:[^\s]+\z/, "")
      computed = SearchQuery.simplify(phrase)
      raise Failure.new("weak_recognition") unless computed
      { "case_id" => id, "source_phrase" => phrase, "phrase" => computed, "source" => "recorded_v1_images_query_before_site",
        "zip" => id == "modern-sofa" ? "94103" : "10001", "parameters" => params.merge("q" => "#{computed} #{params.fetch('q').split.last}") }
    end
  end

  def freeze_manifest!(root: Rails.root)
    root = Pathname(root).realpath
    historical!(root)
    path = root.join(DIRECTORY, "manifest.json")
    raise Failure.new("manifest_already_exists") if path.exist? || root.join(DIRECTORY, "results.json").exist?
    db = DiagnosticV1.open_db(root)
    raise Failure.new("replay_already_started") if table?(db)
    files = [ "#{OLD_DIRECTORY}/manifest.json", "#{OLD_DIRECTORY}/manifest.sha256", "#{OLD_DIRECTORY}/live-evidence.json", "docs/experiments/diagnostic-v1/results.json",
      ARCHIVE, NEW_QUERY, "agent-scratch/diagnostic-v1.rb", "agent-scratch/query-v2.rb" ]
    manifest = { "experiment" => "query-v2", "status" => "prepared_not_run", "frozen_at" => Time.now.utc.iso8601(6), "query_version" => SearchQuery::VERSION,
      "traits" => SearchQuery::TRAITS, "query_aliases" => SearchQuery::QUERY_ALIASES, "max_traits" => SearchQuery::MAX_TRAITS,
      "selection" => "First-seen traits from distinct groups; display color, material, style, then category. Related query first; otherwise repeated traits in the first eight titles.",
      "budget" => { "baseline_search_attempts" => 8, "replay_cap" => 2, "combined_ceiling" => 10, "comparison_ceiling" => 15, "additional_uploads" => 0, "deadline_seconds" => 55, "retries" => 0, "final_smoke_used" => 0 },
      "files" => files.to_h { |name| [ name, digest(root.join(name)) ] }, "cases" => expected_cases(root) }
    # No filesystem or table creation outside this explicit offline freeze.
    File.write(path, JSON.pretty_generate(manifest) + "\n", mode: "wx")
    File.write(root.join(DIRECTORY, "manifest.sha256"), digest(path) + "\n", mode: "wx")
    { "status" => "manifest_frozen", "manifest_sha256" => digest(path), "cases" => manifest.fetch("cases") }
  ensure
    db&.close
  end

  def verify_manifest!(root)
    path = root.join(DIRECTORY, "manifest.json")
    checksum = digest(path)
    raise Failure.new("replay_manifest_changed") unless checksum == File.read(root.join(DIRECTORY, "manifest.sha256")).strip
    manifest = JSON.parse(File.read(path))
    manifest.fetch("files").each { |name, expected| raise Failure.new("frozen_replay_source_changed") unless digest(root.join(name)) == expected }
    historical!(root)
    raise Failure.new("recomputed_query_changed") unless manifest.fetch("cases") == expected_cases(root) && manifest.fetch("query_version") == SearchQuery::VERSION
    [ manifest, checksum ]
  end

  def table?(db)
    !!db.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'query_v2_attempts'")
  end

  def rows(db)
    table?(db) ? db.execute("SELECT * FROM query_v2_attempts ORDER BY reserved_at, case_id") : []
  end

  def baseline!(db, old_checksum, old_evidence)
    DiagnosticV1.original!(db, old_checksum)
    DiagnosticV1.known_evidence!(db, old_evidence)
    previous = DiagnosticV1.rows(db)
    raise Failure.new("diagnostic_baseline_changed") unless previous.length == 2 && previous.all? { |row| row["outcome"] && row["params_sha256"] == DiagnosticV1.params_hash(row["case_id"]) }
  end

  def known_evidence!(db, path, checksum)
    return unless File.exist?(path)
    raise Failure.new("replay_evidence_without_rows") unless table?(db) && File.size(path) <= 100_000
    saved = JSON.parse(File.read(path))
    raise Failure.new("replay_evidence_identity_changed") unless saved.fetch("manifest_sha256") == checksum && saved.fetch("attempts").is_a?(Array) && saved.fetch("attempts").any?
    known = rows(db).to_h { |row| [ row.fetch("case_id"), row ] }
    saved.fetch("attempts").each do |attempt|
      row = known[attempt.fetch("case_id")]
      raise Failure.new("replay_evidence_without_rows") unless row && row["reserved_at"] == attempt["reserved_at"] && row["params_sha256"] == attempt["params_sha256"]
    end
  end

  def preflight(root: Rails.root, deadline: SearchDeadline.new)
    db = nil
    root = Pathname(root).realpath
    deadline.within do
      manifest, checksum = verify_manifest!(root)
      db = DiagnosticV1.open_db(root)
      baseline!(db, manifest.fetch("files").fetch("#{OLD_DIRECTORY}/manifest.json"), root.join("docs/experiments/diagnostic-v1/results.json"))
      known_evidence!(db, root.join(DIRECTORY, "results.json"), checksum)
      current = rows(db)
      raise Failure.new("replay_budget_or_identity_invalid") unless current.length <= 2 && current.map { |row| row["case_id"] } == ORDER.first(current.length) && current.all? { |row| row["manifest_sha256"] == checksum && row["params_sha256"] == encoded_hash(manifest.fetch("cases").find { |item| item["case_id"] == row["case_id"] }.fetch("parameters")) }
      allowance = begin
        DiagnosticV1.allowance!(db, 2 + current.length)
        "ready"
      rescue Failure => error
        error.code
      end
      { "status" => "offline_preflight_passed", "manifest_sha256" => checksum, "baseline_search_attempts" => 8, "replay_attempts" => current.length,
        "combined_search_attempts" => 8 + current.length, "combined_ceiling" => 10, "allowance" => allowance, "cases" => manifest.fetch("cases"), "attempts" => safe_rows(current, manifest) }
    end
  ensure
    db&.close
  end

  def reserve!(db, entry, checksum:, old_checksum:, prior_evidence:, evidence_path:)
    db.transaction(:immediate) do
      baseline!(db, old_checksum, prior_evidence)
      known_evidence!(db, evidence_path, checksum)
      current = rows(db)
      raise Failure.new("duplicate_out_of_order_or_exhausted") unless current.length < 2 && entry.fetch("case_id") == ORDER[current.length] && 8 + current.length < 10
      raise Failure.new("earlier_replay_identity_changed") unless current.all? { |row| row["manifest_sha256"] == checksum }
      DiagnosticV1.allowance!(db, 2 + current.length)
      db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS query_v2_attempts (case_id TEXT PRIMARY KEY CHECK(case_id IN ('modern-sofa','ornate-sofa')), manifest_sha256 TEXT NOT NULL, params_sha256 TEXT NOT NULL, reserved_at TEXT NOT NULL, observed_at TEXT, outcome TEXT);
        CREATE TRIGGER IF NOT EXISTS query_v2_no_delete BEFORE DELETE ON query_v2_attempts BEGIN SELECT RAISE(ABORT, 'Immutable attempt'); END;
        CREATE TRIGGER IF NOT EXISTS query_v2_identity BEFORE UPDATE OF case_id, manifest_sha256, params_sha256, reserved_at ON query_v2_attempts BEGIN SELECT RAISE(ABORT, 'Immutable attempt'); END;
        CREATE TRIGGER IF NOT EXISTS query_v2_once BEFORE UPDATE OF outcome, observed_at ON query_v2_attempts WHEN OLD.outcome IS NOT NULL BEGIN SELECT RAISE(ABORT, 'Outcome recorded'); END;
        CREATE TRIGGER IF NOT EXISTS query_v2_cap BEFORE INSERT ON query_v2_attempts WHEN (SELECT COUNT(*) FROM query_v2_attempts) >= 2 BEGIN SELECT RAISE(ABORT, 'Replay cap'); END;
      SQL
      db.execute("INSERT INTO query_v2_attempts(case_id, manifest_sha256, params_sha256, reserved_at) VALUES (?, ?, ?, ?)", [ entry.fetch("case_id"), checksum, encoded_hash(entry.fetch("parameters")), Time.now.utc.iso8601(6) ])
    end
  end

  def text(value, redact, limit: 500)
    return unless value.is_a?(String) && value.valid_encoding?
    redact.call(value).gsub(%r{https?://\S+}i, "[URL omitted]").gsub(/\b(?:api_key|access_token|client_secret)=\S+/i, "[credential omitted]").gsub(/[[:cntrl:]]/, " ")[0, limit]
  end

  def classify(status, body, entry, redact: ->(value) { value })
    base = { "http_status" => status, "provider_status" => nil, "error_present" => nil }
    return base.merge("classification" => "response_too_large") unless body.is_a?(String) && body.bytesize <= DiagnosticV1::MAX_BYTES
    data = JSON.parse(body)
    return base.merge("classification" => "invalid_json_shape") unless data.is_a?(Hash)
    metadata = data["search_metadata"]
    provider_status = metadata.is_a?(Hash) ? metadata["status"] : nil
    base["provider_status"] = provider_status if %w[Success Error Processing Queued].include?(provider_status)
    base["error_present"] = data.key?("error")
    info = data["search_information"].is_a?(Hash) ? data["search_information"] : {}
    state = info["image_results_state"]
    safe_info = {}
    safe_info["image_results_state"] = state if [ "Results for exact spelling", "Fully empty" ].include?(state)
    %w[query_displayed original_query showing_results_for results_for spelling_fix].each do |field|
      value = text(info[field], redact)
      safe_info[field] = value if value
    end
    base["search_information"] = safe_info
    echo = data["search_parameters"].is_a?(Hash) ? data["search_parameters"]["q"] : nil
    base["query_echo_matches"] = echo.is_a?(String) ? echo == entry.fetch("parameters").fetch("q") : nil
    base["query_echo"] = text(echo, redact)
    known_empty = data["error"].is_a?(String) && NO_RESULTS.match?(data["error"])
    base["known_no_results_wording"] = known_empty
    items = data["images_results"].is_a?(Array) ? data["images_results"] : []
    base["classification"] = if status != 200 then "http_error"
    elsif provider_status == "Success" && items.empty? && (known_empty || state == "Fully empty") then "empty_results"
    elsif data.key?("error") then "unknown_provider_error"
    elsif provider_status != "Success" then "unexpected_provider_status"
    elsif items.empty? then "no_image_results"
    else "results_returned"
    end
    location = LocationResolver.resolve(entry.fetch("zip"))
    normalizer = ListingNormalizer.new(approved_hostnames: LocationResolver::CATALOG.fetch("areas").map { |area| area.fetch("hostname") })
    normalized = normalizer.call(items, location: location, route: "lens_then_images", query: entry.fetch("phrase"))
    candidates = normalized.listings.map do |listing|
      listing.to_h { |key, value| [ key.to_s, %i[url thumbnail].include?(key) ? redact.call(value) : text(value, redact, limit: 300) ] }
    end
    base.merge("normalizer_counts" => normalized.counts, "candidates" => candidates, **DiagnosticV1.url_summary(items, normalizer, location.hostname, redact))
  rescue JSON::ParserError
    base.merge("classification" => "invalid_json")
  end

  def safe_rows(records, manifest)
    records.map do |row|
      entry = manifest.fetch("cases").find { |item| item["case_id"] == row.fetch("case_id") }
      { "case_id" => row.fetch("case_id"), "params_sha256" => row.fetch("params_sha256"), "reserved_at" => row.fetch("reserved_at"),
        "parameters" => entry.fetch("parameters"), "observed_at" => row["observed_at"], "outcome" => row["outcome"] ? JSON.parse(row["outcome"]) : { "classification" => "reserved_dispatch_uncertain" } }
    end
  end

  def observe!(db, entry, checksum:, old_checksum:, prior_evidence:, evidence_path:, deadline:, transport: DiagnosticV1.method(:fetch))
    deadline.remaining
    reserve!(db, entry, checksum: checksum, old_checksum: old_checksum, prior_evidence: prior_evidence, evidence_path: evidence_path)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = begin
      deadline.within do
        status, body, redact = begin
          transport.call(entry.fetch("parameters"), deadline)
        rescue SearchDeadline::Exceeded, Failure
          raise
        rescue StandardError
          raise Failure.new("transport_error"), cause: nil
        end
        classify(status, body, entry, redact: redact || ->(value) { value })
      end
    rescue SearchDeadline::Exceeded
      { "classification" => "deadline" }
    rescue Failure => error
      { "classification" => error.code, "http_status" => error.http_status }
    rescue StandardError
      { "classification" => "probe_processing_error" }
    end
    result["elapsed_ms"] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3)
    db.transaction(:immediate) do
      db.execute("UPDATE query_v2_attempts SET observed_at = ?, outcome = ? WHERE case_id = ? AND outcome IS NULL", [ Time.now.utc.iso8601(6), JSON.generate(result), entry.fetch("case_id") ])
      raise Failure.new("outcome_already_recorded") unless db.changes == 1
    end
    result
  end

  def execute(id, root: Rails.root)
    raise Failure.new("unapproved_case") unless ORDER.include?(id)
    deadline = SearchDeadline.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    preflight(root: root, deadline: deadline)
    root = Pathname(root).realpath
    manifest, checksum = verify_manifest!(root)
    entry = manifest.fetch("cases").find { |item| item["case_id"] == id }
    db = DiagnosticV1.open_db(root, writable: true)
    path = root.join(DIRECTORY, "results.json")
    observe!(db, entry, checksum: checksum, old_checksum: manifest.fetch("files").fetch("#{OLD_DIRECTORY}/manifest.json"), prior_evidence: root.join("docs/experiments/diagnostic-v1/results.json"), evidence_path: path, deadline: deadline)
    current = rows(db)
    report = { "experiment" => "query-v2", "manifest_sha256" => checksum, "baseline_search_attempts" => 8, "replay_attempts" => current.length, "combined_search_attempts" => 8 + current.length,
      "combined_ceiling" => 10, "additional_uploads" => 0, "final_smoke_used" => 0, "execution_elapsed_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3),
      "meaning" => "Two saved-phrase Images observations only; not a full route pass or a replacement for historical scores. Reservations count on failure and cache hits.", "attempts" => safe_rows(current, manifest) }
    payload = JSON.pretty_generate(report) + "\n"
    raise Failure.new("evidence_too_large") if payload.bytesize > 100_000
    temp = "#{path}.tmp-#{Process.pid}"
    File.write(temp, payload, mode: "wx", perm: 0o600)
    File.rename(temp, path)
    report
  ensure
    db&.close
    File.delete(temp) if temp && File.exist?(temp)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    result = if ARGV.empty? then QueryV2.preflight
    elsif ARGV == [ "--freeze" ] then QueryV2.freeze_manifest!
    elsif ARGV.length == 2 && ARGV.first == "--execute" then QueryV2.execute(ARGV.last)
    else raise QueryV2::Failure.new("usage_preflight_freeze_or_execute_approved_case")
    end
    puts JSON.pretty_generate(result)
  rescue QueryV2::Failure => error
    warn "Replay stopped: #{error.code}. Reserved attempts remain spent."
    exit 1
  rescue StandardError
    warn "Replay stopped safely. Inspect existing reservations; do not retry an uncertain case."
    exit 1
  end
end

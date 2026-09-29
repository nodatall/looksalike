#!/usr/bin/env ruby
# Two user-approved marketplace probes; importing helpers makes no live calls.
require_relative "query-v2"

module EbayV1
  extend self
  DIR = Rails.root.join("docs/experiments/ebay-v1")
  BASE_TABLES = %w[identity cases attempts account_checks diagnostic_v1_attempts query_v2_attempts].freeze
  CASES = QueryV2.expected_cases(Rails.root).map do |entry|
    { "case_id" => entry.fetch("case_id"), "parameters" => {
      "engine" => "ebay", "_nkw" => entry.fetch("phrase"), "ebay_domain" => "ebay.com",
      "_stpos" => entry.fetch("zip"), "show_only" => "LPickup", "LH_PrefLoc" => "Domestic", "_ipg" => "25"
    } }
  end.freeze

  def hash(value) = Digest::SHA256.hexdigest(JSON.generate(value))
  def write_once(path, value) = File.write(path, JSON.pretty_generate(value) + "\n", mode: "wx", perm: 0o600)
  def baseline(db) = BASE_TABLES.to_h { |name| [name, hash(db.execute("SELECT * FROM #{name} ORDER BY rowid"))] }
  def records(db)
    return [] unless db.get_first_value("SELECT 1 FROM sqlite_master WHERE type='table' AND name='ebay_v1_attempts'")
    db.execute("SELECT * FROM ebay_v1_attempts ORDER BY reserved_at")
  end

  def freeze!
    pre = QueryV2.preflight
    raise "Unexpected baseline" unless pre.fetch("combined_search_attempts") == 10
    db = DiagnosticV1.open_db(Rails.root)
    raise "Already started" unless records(db).empty?
    FileUtils.mkdir_p(DIR)
    manifest = { "experiment" => "ebay-v1", "frozen_at" => Time.now.utc.iso8601,
      "authorization" => "User approved trying the two existing sofa queries on eBay.",
      "baseline_search_attempts" => 10, "max_new_attempts" => 2, "combined_ceiling" => 12,
      "comparison_ceiling" => 15, "additional_uploads" => 0, "retries" => 0, "deadline_seconds" => 55,
      "cases" => CASES, "prior_tables" => baseline(db),
      "files" => %w[agent-scratch/ebay-v1.rb agent-scratch/query-v2.rb agent-scratch/diagnostic-v1.rb docs/experiments/query-v2/manifest.json docs/experiments/query-v2/results.json].to_h { |p| [p, QueryV2.digest(Rails.root.join(p))] },
      "review" => "Inspect the first six distinct item links in provider order, their photos, prices, shipping and locations. Postal-code and pickup filters do not establish a distance guarantee. This is not a full photo-to-listings validation." }
    write_once(DIR.join("manifest.json"), manifest)
    File.write(DIR.join("manifest.sha256"), QueryV2.digest(DIR.join("manifest.json")) + "\n", mode: "wx")
    { status: "frozen", cases: CASES }
  ensure
    db&.close
  end

  def verify(db)
    path = DIR.join("manifest.json")
    checksum = QueryV2.digest(path)
    raise "Manifest changed" unless checksum == File.read(DIR.join("manifest.sha256")).strip
    manifest = JSON.parse(File.read(path))
    raise "Prior ledger changed" unless manifest.fetch("prior_tables") == baseline(db)
    raise "Cases changed" unless manifest.fetch("cases") == CASES
    manifest.fetch("files").each { |p, digest| raise "Source changed" unless QueryV2.digest(Rails.root.join(p)) == digest }
    QueryV2.verify_manifest!(Rails.root)
    rows = records(db)
    raise "Unexpected attempts" unless rows.length <= 2 && rows.map { |r| r["case_id"] } == CASES.first(rows.length).map { |c| c["case_id"] }
    rows.each { |r| raise "Attempt changed" unless r["manifest_sha256"] == checksum && r["params_sha256"] == hash(CASES.find { |c| c["case_id"] == r["case_id"] }.fetch("parameters")) }
    checksum
  end

  def account!
    db = DiagnosticV1.open_db(Rails.root)
    verify(db)
    raise "Account already checked or search started" if DIR.join("account.json").exist? || records(db).any?
    summary = SerpApi::Client.new.account(deadline: SearchDeadline.new)
    raise "Insufficient account allowance" unless summary["account_status"] == "Active" && summary["total_searches_left"] >= 2
    write_once(DIR.join("account.json"), summary.merge("checked_at" => Time.now.utc.iso8601, "attempts_at_check" => 10))
    summary
  ensure
    db&.close
  end

  def text(value, redact)
    return nil unless value.is_a?(String)
    redact.call(value).gsub(%r{https?://\S+}, "[URL omitted]").gsub(/[[:cntrl:]]/, " ")[0, 500]
  end

  def classify(status, body, redact)
    data = JSON.parse(body)
    items = data["organic_results"].is_a?(Array) ? data["organic_results"] : []
    params = data["search_parameters"].is_a?(Hash) ? data["search_parameters"].slice(*CASES.first.fetch("parameters").keys) : {}
    listings = items.first(100).each_with_index.map do |item, index|
      link = URI(item["link"].to_s) rescue nil
      id = link&.path&.match(%r{\A/itm/(?:[^/]+/)?(\d+)\z})&.[](1)
      url = "https://www.ebay.com/itm/#{id}" if id && %w[ebay.com www.ebay.com].include?(link.host) && link.scheme == "https"
      thumb = URI(item["thumbnail"].to_s) rescue nil
      thumbnail = thumb.to_s if thumb&.scheme == "https" && thumb.host == "i.ebayimg.com" && !thumb.userinfo
      row = { "position" => index + 1, "url" => url, "thumbnail" => thumbnail, "sponsored" => item["sponsored"] == true }
      %w[title subtitle condition shipping location buying_format].each { |key| row[key] = text(item[key], redact) }
      price = item["price"]
      if price.is_a?(Hash)
        row["price"] = price.slice("raw", "from", "to").transform_values { |v| v.is_a?(Hash) ? text(v["raw"], redact) : text(v, redact) }
      end
      row
    end
    state = data.dig("search_metadata", "status")
    { "http_status" => status, "provider_status" => %w[Success Error Processing Queued].include?(state) ? state : nil,
      "error" => text(data["error"], redact), "parameters_echo" => params.transform_values { |v| text(v.to_s, redact) },
      "search_information" => (data["search_information"].is_a?(Hash) ? data["search_information"] : {}).slice("organic_results_state", "total_results", "query_displayed").transform_values { |v| v.is_a?(Numeric) ? v : text(v, redact) },
      "classification" => status == 200 && state == "Success" && !data.key?("error") ? "results_returned" : "provider_error",
      "returned_items" => items.length, "listings" => listings }
  end

  def execute(id)
    entry = CASES.find { |c| c["case_id"] == id }
    raise "Unapproved case" unless entry
    db = DiagnosticV1.open_db(Rails.root, writable: true)
    db.transaction(:immediate) do
      checksum = verify(db)
      previous = records(db)
      raise "Duplicate or exhausted" unless previous.length < 2 && CASES[previous.length] == entry
      account = JSON.parse(File.read(DIR.join("account.json")))
      raise "Stale allowance" unless (Time.now.utc - Time.iso8601(account.fetch("checked_at"))).between?(0, 3600) && account.fetch("total_searches_left") - previous.length >= 1
      db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS ebay_v1_attempts(case_id TEXT PRIMARY KEY, manifest_sha256 TEXT NOT NULL, params_sha256 TEXT NOT NULL, reserved_at TEXT NOT NULL, outcome TEXT);
        CREATE TRIGGER IF NOT EXISTS ebay_v1_cap BEFORE INSERT ON ebay_v1_attempts WHEN (SELECT COUNT(*) FROM ebay_v1_attempts)>=2 BEGIN SELECT RAISE(ABORT,'Attempt cap'); END;
        CREATE TRIGGER IF NOT EXISTS ebay_v1_no_delete BEFORE DELETE ON ebay_v1_attempts BEGIN SELECT RAISE(ABORT,'Immutable'); END;
        CREATE TRIGGER IF NOT EXISTS ebay_v1_identity BEFORE UPDATE OF case_id,manifest_sha256,params_sha256,reserved_at ON ebay_v1_attempts BEGIN SELECT RAISE(ABORT,'Immutable'); END;
        CREATE TRIGGER IF NOT EXISTS ebay_v1_once BEFORE UPDATE OF outcome ON ebay_v1_attempts WHEN OLD.outcome IS NOT NULL BEGIN SELECT RAISE(ABORT,'Recorded'); END;
      SQL
      db.execute("INSERT INTO ebay_v1_attempts(case_id,manifest_sha256,params_sha256,reserved_at) VALUES (?,?,?,?)", [id, checksum, hash(entry.fetch("parameters")), Time.now.utc.iso8601(6)])
    end
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = begin
      status, body, redact = DiagnosticV1.fetch(entry.fetch("parameters"), SearchDeadline.new)
      classify(status, body, redact)
    rescue StandardError => error
      { "classification" => "request_or_processing_failed", "error_class" => error.class.name }
    end
    result["elapsed_ms"] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - began) * 1000).round(3)
    db.execute("UPDATE ebay_v1_attempts SET outcome=? WHERE case_id=? AND outcome IS NULL", [JSON.generate(result), id])
    raise "Outcome update failed" unless db.changes == 1
    write_once(DIR.join("#{id}.json"), entry.merge("reserved_at" => records(db).find { |r| r["case_id"] == id }.fetch("reserved_at"), "outcome" => result))
    { case_id: id, combined_attempts: 10 + records(db).length, outcome: result }
  ensure
    db&.close
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    result = case ARGV
    when ["--freeze"] then EbayV1.freeze!
    when ["--account"] then EbayV1.account!
    when ["--execute", "modern-sofa"], ["--execute", "ornate-sofa"] then EbayV1.execute(ARGV.last)
    else
      db = DiagnosticV1.open_db(Rails.root)
      EbayV1.verify(db)
      { status: "verified", cumulative_search_attempts: 10 + EbayV1.records(db).length }
    end
    puts JSON.pretty_generate(result)
  rescue StandardError => error
    warn "eBay probe stopped (#{error.class.name}); no automatic retries."
    exit 1
  ensure
    db&.close
  end
end

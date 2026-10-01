require "json"
require "fileutils"

class ExperimentRunner
  def initialize(root: Rails.root, client: nil, ledger_path: nil)
    @root = Pathname(root).realpath
    @client = client
    @ledger_path = ledger_path || @root.join("storage/feasibility-v1.sqlite3")
  end

  def preflight
    manifest = ExperimentManifest.new(root: @root).verify!
    { "status" => "offline_preflight_passed", "manifest_sha256" => manifest.checksum,
      "cases" => manifest.data.fetch("cases").map { |entry| { "id" => entry.fetch("id"), "zip" => entry.fetch("zip"), "host" => entry.fetch("location").fetch("hostname") } },
      "ledger_exists" => File.file?(@ledger_path), "searches_dispatched" => 0 }
  end

  def initialize_ledger!
    manifest = ExperimentManifest.new(root: @root).verify!
    raise ExperimentLedger::Error, "Existing live evidence prevents ledger initialization; restore the original ledger" if @root.join("docs/experiments/feasibility-v1/live-evidence.json").exist?
    with_ledger(manifest, create: true) { { "status" => "ledger_initialized", "manifest_sha256" => manifest.checksum, "search_attempts" => 0 } }
  end

  def account!
    manifest = ExperimentManifest.new(root: @root).verify!
    with_ledger(manifest) do |ledger|
      baseline = ledger.search_count
      checked_at = Time.now.utc
      summary = @client.account(deadline: SearchDeadline.new)
      ledger.record_account!(summary, attempts_at_check: baseline, checked_at: checked_at)
      summary.merge("allowance_valid_for_seconds" => ExperimentLedger::ACCOUNT_MAX_AGE)
    end
  end

  def run!(route:)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    deadline = SearchDeadline.new
    manifest = ExperimentManifest.new(root: @root).verify!(deadline: deadline)
    with_ledger(manifest) do |ledger|
      case_id = ledger.next_case(route)
      entry = manifest.data.fetch("cases").find { |candidate| candidate.fetch("id") == case_id }
      photo = manifest.photo(entry)
      deadline.remaining
      ledger.begin_case!(route: route, case_id: case_id)
      outcome = FurnitureSearch.new(client: @client, accounting: ->(stage) { ledger.reserve!(route: route, case_id: case_id, stage: stage) }).call(
        photo: photo, zip: entry.fetch("zip"), route: route, deadline: deadline, started_at: started)
      ledger.finish!(route: route, case_id: case_id, outcome: outcome)
      export(ledger)
      { "route" => route, "case_id" => case_id, "technical_status" => outcome.fetch("status"), "candidate_count" => outcome.fetch("listings").length, "search_attempts" => ledger.search_count, "next" => "Inspect the original candidates and record a manual judgment." }
    end
  end

  def score!(route:, case_id:, judgment:)
    manifest = ExperimentManifest.new(root: @root).verify!
    require_existing_ledger!
    with_ledger(manifest) do |ledger|
      result = ledger.judge!(route: route, case_id: case_id, judgment: judgment)
      export(ledger)
      result
    end
  end

  def report
    manifest = ExperimentManifest.new(root: @root).verify!
    require_existing_ledger!
    with_ledger(manifest) { |ledger| ledger.report }
  end

  def export!
    manifest = ExperimentManifest.new(root: @root).verify!
    require_existing_ledger!
    with_ledger(manifest) { |ledger| export(ledger); { "status" => "exported" } }
  end

  private
    def require_existing_ledger!
      raise ExperimentLedger::Error, "No experiment ledger exists" unless File.file?(@ledger_path)
    end

    def with_ledger(manifest, create: false)
      ledger = ExperimentLedger.new(path: @ledger_path, expected_path: @root.join("storage/feasibility-v1.sqlite3"), manifest_checksum: manifest.checksum,
        case_ids: manifest.data.fetch("cases").map { |entry| entry.fetch("id") }, create: create)
      yield ledger
    ensure
      ledger&.close
    end

    def export(ledger)
      # Only ledger-owned sanitized outcomes/judgments, never raw responses.
      path = @root.join("docs/experiments/feasibility-v1/live-evidence.json")
      payload = JSON.pretty_generate(ledger.report) + "\n"
      raise ExperimentLedger::Error, "Evidence exceeded its bounded size" if payload.bytesize > 250_000
      temp = "#{path}.tmp-#{Process.pid}"
      File.write(temp, payload, mode: "wx", perm: 0o600)
      File.rename(temp, path)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end
end

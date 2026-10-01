require "sqlite3"
require "json"
require "time"

# Manual experiment storage only. Public quotas/cache remain separate Rails work.
class ExperimentLedger
  class Error < StandardError; end
  ROUTE_CAPS = { "lens_only" => 5, "lens_then_images" => 10 }.freeze
  TOTAL_CAP = 15
  ACCOUNT_MAX_AGE = 3600
  CARD_FLAGS = %w[category_match style_match distinct correct_area accessible].freeze

  def initialize(path:, expected_path:, manifest_checksum:, case_ids:, create: false, clock: -> { Time.now.utc })
    @path = File.expand_path(path)
    expected = File.expand_path(expected_path)
    parent = File.dirname(expected)
    raise Error, "Ledger path is not the intended writable local file" unless @path == expected && File.directory?(parent) && File.realpath(parent) == parent && !File.symlink?(@path) && File.writable?(parent)
    raise Error, "Ledger is not writable" if File.exist?(@path) && !File.writable?(@path)
    @checksum, @case_ids, @clock = manifest_checksum, case_ids, clock
    raise Error, "Exactly five unique cases are required" unless case_ids.size == 5 && case_ids.uniq.size == 5
    raise Error, "Ledger already exists; initialization cannot reset it" if create && File.exist?(@path)
    raise Error, "Initialize the local experiment ledger explicitly before provider operations" unless create || File.file?(@path)
    flags = SQLite3::Constants::Open::READWRITE
    flags |= SQLite3::Constants::Open::CREATE if create
    @db = SQLite3::Database.new(@path, flags: flags)
    @db.results_as_hash = true
    @db.busy_timeout = 5000
    @db.execute("PRAGMA foreign_keys = ON")
    @db.execute("PRAGMA synchronous = FULL")
    create ? setup! : verify_identity!
  rescue Error
    @db&.close
    raise
  rescue SQLite3::Exception, SystemCallError
    @db&.close
    raise Error, "Experiment ledger is unavailable", cause: nil
  end

  def close
    @db.close
  end

  def record_account!(summary, attempts_at_check: search_count, checked_at: @clock.call)
    left = summary["total_searches_left"]
    raise Error, "Account is not active or has no validated allowance" unless summary["account_status"] == "Active" && left.is_a?(Integer) && left >= 0
    transaction do
      raise Error, "Invalid account check baseline" unless attempts_at_check.is_a?(Integer) && attempts_at_check.between?(0, search_count)
      @db.execute("INSERT INTO account_checks(checked_at, searches_left, attempts_at_check) VALUES (?, ?, ?)", [ checked_at.utc.iso8601(6), left, attempts_at_check ])
    end
  end

  def require_allowance!(needed:)
    account = @db.get_first_row("SELECT * FROM account_checks ORDER BY id DESC LIMIT 1")
    raise Error, "Run an explicit account check before dispatch (valid for one hour)" unless account && (@clock.call - Time.iso8601(account["checked_at"])).between?(0, ACCOUNT_MAX_AGE)
    left = account["searches_left"] - (search_count - account["attempts_at_check"])
    raise Error, "Recorded account allowance is insufficient" if left < needed
    left
  end

  def next_case(route)
    raise Error, "Unsupported route" unless ROUTE_CAPS.key?(route)
    lens = cases("lens_only")
    raise Error, "Lens-only must have two judged failures first" if route == "lens_then_images" && failures(lens) < 2
    rows = cases(route)
    raise Error, "Finish the previous manual judgment before advancing" if rows.any? { |row| row["judgment"].nil? }
    raise Error, "Route stopped after two failed cases; remaining cases are untested" if failures(rows) >= 2
    raise Error, "Route is complete" if rows.length == @case_ids.length
    @case_ids.fetch(rows.length)
  end

  def begin_case!(route:, case_id:)
    transaction do
      raise Error, "Case is out of order or was already claimed" unless next_case(route) == case_id
      require_allowance!(needed: route == "lens_only" ? 1 : 2)
      @db.execute("INSERT INTO cases(route, case_id, started_at) VALUES (?, ?, ?)", [ route, case_id, now ])
    end
  end

  def reserve!(route:, case_id:, stage:)
    transaction do
      row = case_record(route, case_id)
      raise Error, "Case is not open" unless row && row["outcome"].nil? && row["judgment"].nil?
      raise Error, "Unsupported stage" unless %w[upload lens images].include?(stage) && !(route == "lens_only" && stage == "images")
      stages = @db.execute("SELECT stage FROM attempts WHERE route = ? AND case_id = ? ORDER BY id", [ route, case_id ]).map { |item| item["stage"] }
      expected = %w[upload lens images][stages.length]
      raise Error, "Stage already attempted or out of order" unless stage == expected
      if stage != "upload"
        raise Error, "Experiment search budget exhausted" if search_count >= TOTAL_CAP || search_count(route) >= ROUTE_CAPS.fetch(route)
        require_allowance!(needed: 1)
      end
      @db.execute("INSERT INTO attempts(route, case_id, stage, reserved_at) VALUES (?, ?, ?, ?)", [ route, case_id, stage, now ])
    end
  end

  def finish!(route:, case_id:, outcome:)
    transaction do
      row = case_record(route, case_id)
      raise Error, "Case cannot be finished twice" unless row && row["outcome"].nil? && row["judgment"].nil?
      @db.execute("UPDATE cases SET outcome = ?, finished_at = ? WHERE route = ? AND case_id = ?", [ JSON.generate(outcome), now, route, case_id ])
    end
  end

  def judge!(route:, case_id:, judgment:)
    transaction do
      row = case_record(route, case_id)
      raise Error, "Case missing or already judged" unless row && row["judgment"].nil?
      outcome = row["outcome"] || { "status" => "interrupted", "listings" => [], "elapsed_ms" => nil }
      listings = outcome.fetch("listings")
      cards = judgment["cards"]
      raise Error, "Judgment needs a reason and exactly the original cards" unless reason?(judgment["reason"]) && cards.is_a?(Array) && cards.length == listings.length
      cards.each_with_index do |card, index|
        raise Error, "Every card needs its original index, reason, and five boolean observations" unless card.is_a?(Hash) && card["position"] == index + 1 && reason?(card["reason"]) && CARD_FLAGS.all? { |flag| [ true, false ].include?(card[flag]) }
      end
      passing = cards.count { |card| CARD_FLAGS.all? { |flag| card[flag] } }
      passed = outcome["status"] == "success" && outcome["elapsed_ms"].is_a?(Numeric) && outcome["elapsed_ms"] <= 55_000 && passing >= 3
      safe = { "reason" => judgment["reason"], "cards" => cards.map { |card| card.slice("position", "reason", *CARD_FLAGS) }, "passing_cards" => passing, "passed" => passed, "judged_at" => now }
      @db.execute("UPDATE cases SET judgment = ?, outcome = COALESCE(outcome, ?), finished_at = COALESCE(finished_at, ?) WHERE route = ? AND case_id = ?", [ JSON.generate(safe), JSON.generate(outcome), now, route, case_id ])
      safe
    end
  end

  def search_count(route = nil)
    sql = "SELECT COUNT(*) FROM attempts WHERE stage != 'upload'"
    route ? @db.get_first_value("#{sql} AND route = ?", [ route ]) : @db.get_first_value(sql)
  end

  def case_record(route, case_id)
    decode(@db.get_first_row("SELECT * FROM cases WHERE route = ? AND case_id = ?", [ route, case_id ]))
  end

  def cases(route)
    @db.execute("SELECT * FROM cases WHERE route = ? ORDER BY rowid", [ route ]).map { |row| decode(row) }
  end

  def report
    { "manifest_sha256" => @checksum, "search_attempts" => search_count, "comparison_cap" => TOTAL_CAP,
      "upload_attempts" => @db.get_first_value("SELECT COUNT(*) FROM attempts WHERE stage = 'upload'"),
      "attempt_semantics" => "Reserved before dispatch; an interrupted request may have an uncertain outcome.",
      "attempts" => @db.execute("SELECT route, case_id, stage, reserved_at FROM attempts ORDER BY id"),
      "routes" => ROUTE_CAPS.keys.to_h { |route| rows = cases(route); [ route, { "cases" => rows, "passed" => rows.length == 5 && rows.count { |row| row.dig("judgment", "passed") == true } >= 4, "stopped" => failures(rows) >= 2, "untested" => @case_ids - rows.map { |row| row["case_id"] } } ] } }
  end

  private
    def now
      @clock.call.iso8601(6)
    end

    def reason?(value)
      value.is_a?(String) && value.valid_encoding? && value.bytesize <= 2000 && value.strip.length.between?(1, 500) && !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f]/)
    end

    def failures(rows)
      rows.count { |row| row.dig("judgment", "passed") == false }
    end

    def decode(row)
      return unless row
      row.dup.tap do |result|
        %w[outcome judgment].each { |key| result[key] = JSON.parse(result[key]) if result[key] }
      end
    end

    def transaction(&block)
      @db.transaction(:immediate, &block)
    rescue SQLite3::Exception
      raise Error, "Experiment ledger rejected the operation", cause: nil
    end

    def verify_identity!
      identity = @db.get_first_row("SELECT * FROM identity WHERE id = 1")
      raise Error, "Ledger belongs to a different frozen manifest" unless identity && identity["manifest"] == @checksum && JSON.parse(identity["cases"]) == @case_ids
    end

    def setup!
      transaction do
        @db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS identity (id INTEGER PRIMARY KEY CHECK(id = 1), manifest TEXT NOT NULL, cases TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS cases (route TEXT NOT NULL, case_id TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT, outcome TEXT, judgment TEXT, PRIMARY KEY(route, case_id));
          CREATE TABLE IF NOT EXISTS attempts (id INTEGER PRIMARY KEY, route TEXT NOT NULL, case_id TEXT NOT NULL, stage TEXT NOT NULL, reserved_at TEXT NOT NULL, UNIQUE(route, case_id, stage), FOREIGN KEY(route, case_id) REFERENCES cases(route, case_id));
          CREATE TABLE IF NOT EXISTS account_checks (id INTEGER PRIMARY KEY, checked_at TEXT NOT NULL, searches_left INTEGER NOT NULL, attempts_at_check INTEGER NOT NULL);
          CREATE TRIGGER IF NOT EXISTS immutable_attempt_update BEFORE UPDATE ON attempts BEGIN SELECT RAISE(ABORT, 'Attempts are immutable'); END;
          CREATE TRIGGER IF NOT EXISTS immutable_attempt_delete BEFORE DELETE ON attempts BEGIN SELECT RAISE(ABORT, 'Attempts are immutable'); END;
        SQL
        identity = @db.get_first_row("SELECT * FROM identity WHERE id = 1")
        if identity
          raise Error, "Ledger belongs to a different frozen manifest" unless identity["manifest"] == @checksum && JSON.parse(identity["cases"]) == @case_ids
        else
          @db.execute("INSERT INTO identity(id, manifest, cases) VALUES (1, ?, ?)", [ @checksum, JSON.generate(@case_ids) ])
        end
      end
    end
end

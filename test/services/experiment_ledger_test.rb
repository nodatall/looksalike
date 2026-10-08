require "test_helper"
require_relative "../support/experiment_helpers"
require "open3"

class ExperimentLedgerTest < ActiveSupport::TestCase
  include ExperimentHelpers
  setup { prepare_experiment }
  teardown { FileUtils.remove_entry(@temporary) }

  test "attempts precede transport, never refund, and survive a new process" do
    with_store do |ledger|
      allowance(ledger)
      ledger.begin_case!(route: "lens_only", case_id: IDS.first)
      ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: "upload")
      assert_equal 0, ledger.search_count
      assert_raises(IOError) do
        ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: "lens")
        raise IOError, "offline transport failure"
      end
      assert_equal 1, ledger.search_count
      assert_equal %w[upload lens], ledger.report.fetch("attempts").map { |attempt| attempt.fetch("stage") }
      assert ledger.report.fetch("attempts").all? { |attempt| attempt.keys.sort == %w[case_id reserved_at route stage] }
      assert_raises(ExperimentLedger::Error) { ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: "lens") }
    end
    script = 'require "experiment_ledger"; store = ExperimentLedger.new(path: ARGV[0], expected_path: ARGV[0], manifest_checksum: ARGV[1], case_ids: ARGV[2].split(",")); puts store.search_count; store.close'
    output, status = Open3.capture2(RbConfig.ruby, "-I", Rails.root.join("app/services").to_s, "-r", "bundler/setup", "-e", script, @path.to_s, @checksum, IDS.join(","))
    assert status.success?
    assert_equal "1", output.strip
  end

  test "two distinct concurrent reservations at a bounded cap permit exactly one" do
    with_store { |ledger| allowance(ledger) }
    db = SQLite3::Database.new(@path.to_s)
    now = Time.now.utc.iso8601
    IDS.first(2).each do |id|
      db.execute("INSERT INTO cases(route, case_id, started_at) VALUES ('lens_only', ?, ?)", [ id, now ])
      db.execute("INSERT INTO attempts(route, case_id, stage, reserved_at) VALUES ('lens_only', ?, 'upload', ?)", [ id, now ])
    end
    db.close
    # Distinct eligible cases isolate the cap from duplicate-stage protection.
    stub_const(ExperimentLedger, :TOTAL_CAP, 1) do
      ready = Queue.new
      go = Queue.new
      threads = IDS.first(2).map do |id|
        Thread.new do
          ledger = store
          ready << true
          go.pop
          begin
            ledger.reserve!(route: "lens_only", case_id: id, stage: "lens")
            :reserved
          rescue ExperimentLedger::Error
            :rejected
          ensure
            ledger.close
          end
        end
      end
      2.times { ready.pop }
      2.times { go << true }
      assert_equal [ :rejected, :reserved ], threads.map(&:value).sort
      with_store { |ledger| assert_equal 1, ledger.search_count }
    end
  end

  test "both total and per-route exhausted budgets block before reservation" do
    with_store do |ledger|
      allowance(ledger)
      ledger.begin_case!(route: "lens_only", case_id: IDS.first)
      ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: "upload")
      stub_const(ExperimentLedger, :TOTAL_CAP, 0) do
        assert_raises(ExperimentLedger::Error) { ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: "lens") }
      end
      stub_const(ExperimentLedger, :ROUTE_CAPS, { "lens_only" => 0, "lens_then_images" => 10 }) do
        assert_raises(ExperimentLedger::Error) { ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: "lens") }
      end
      assert_equal 0, ledger.search_count
    end
  end

  test "manual order, duplicate claim, interrupted failure and route stop persist" do
    with_store do |ledger|
      allowance(ledger)
      assert_raises(ExperimentLedger::Error) { ledger.next_case("lens_then_images") }
      ledger.begin_case!(route: "lens_only", case_id: IDS.first)
      assert_raises(ExperimentLedger::Error) { ledger.begin_case!(route: "lens_only", case_id: IDS.first) }
      assert_raises(ExperimentLedger::Error) { ledger.next_case("lens_only") }
      result = ledger.judge!(route: "lens_only", case_id: IDS.first, judgment: judgment(count: 0))
      refute result["passed"]
      assert_equal "interrupted", ledger.case_record("lens_only", IDS.first).dig("outcome", "status")
      ledger.begin_case!(route: "lens_only", case_id: IDS[1])
      ledger.finish!(route: "lens_only", case_id: IDS[1], outcome: outcome(count: 2))
      refute ledger.judge!(route: "lens_only", case_id: IDS[1], judgment: judgment(count: 2))["passed"]
      assert_raises(ExperimentLedger::Error) { ledger.next_case("lens_only") }
      assert_equal IDS.first, ledger.next_case("lens_then_images")
      assert_equal IDS.drop(2), ledger.report.dig("routes", "lens_only", "untested")
    end
  end

  test "four of five passes prefer Lens-only and observations cannot replace cards" do
    with_store do |ledger|
      allowance(ledger)
      IDS.each_with_index do |id, index|
        ledger.begin_case!(route: "lens_only", case_id: id)
        ledger.finish!(route: "lens_only", case_id: id, outcome: outcome(elapsed_ms: index == 4 ? 55_001 : 1000))
        assert_raises(ExperimentLedger::Error) { ledger.judge!(route: "lens_only", case_id: id, judgment: judgment(count: 2)) }
        result = ledger.judge!(route: "lens_only", case_id: id, judgment: judgment)
        assert_equal index != 4, result["passed"]
        assert_raises(ExperimentLedger::Error) { ledger.judge!(route: "lens_only", case_id: id, judgment: judgment) }
      end
      assert ledger.report.dig("routes", "lens_only", "passed")
      assert_raises(ExperimentLedger::Error) { ledger.next_case("lens_then_images") }
    end
  end

  test "allowance is conservative after attempts and stale checks block" do
    time = Time.now.utc
    ledger = store(clock: -> { time })
    ledger.record_account!({ "account_status" => "Active", "total_searches_left" => 1 })
    ledger.begin_case!(route: "lens_only", case_id: IDS.first)
    %w[upload lens].each { |stage| ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: stage) }
    assert_raises(ExperimentLedger::Error) { ledger.require_allowance!(needed: 1) }
    ledger.record_account!({ "account_status" => "Active", "total_searches_left" => 10 }, attempts_at_check: 0)
    assert_equal 9, ledger.require_allowance!(needed: 1)
    time += 3601
    assert_raises(ExperimentLedger::Error) { ledger.require_allowance!(needed: 1) }
  ensure
    ledger&.close
  end

  test "missing directory, wrong identity, and immutable attempt mutation fail closed" do
    assert_raises(ExperimentLedger::Error) { ExperimentLedger.new(path: @root.join("missing/db"), expected_path: @root.join("missing/db"), manifest_checksum: @checksum, case_ids: IDS) }
    with_store do |ledger|
      allowance(ledger)
      ledger.begin_case!(route: "lens_only", case_id: IDS.first)
      ledger.reserve!(route: "lens_only", case_id: IDS.first, stage: "upload")
    end
    assert_raises(ExperimentLedger::Error) { ExperimentLedger.new(path: @path, expected_path: @path, manifest_checksum: "changed", case_ids: IDS) }
    db = SQLite3::Database.new(@path.to_s)
    assert_raises(SQLite3::ConstraintException) { db.execute("DELETE FROM attempts") }
    assert_raises(SQLite3::ConstraintException) { db.execute("UPDATE attempts SET stage = 'lens'") }
  ensure
    db&.close
  end
end

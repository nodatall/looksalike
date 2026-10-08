require "test_helper"
require_relative "../support/experiment_helpers"

class ExperimentRunnerTest < ActiveSupport::TestCase
  include ExperimentHelpers
  setup { prepare_experiment }
  teardown { FileUtils.remove_entry(@temporary) }

  test "dry preflight validates real bytes and never creates a ledger or calls a provider" do
    result = ExperimentRunner.new(root: @root).preflight
    assert_equal "offline_preflight_passed", result["status"]
    refute File.exist?(@path)
    refute File.exist?(@root.join("docs/experiments/feasibility-v1/live-evidence.json"))
    assert_empty @calls
  end

  test "changed manifest, invalid photo, invalid ZIP, missing storage all stop before calls" do
    manifest_path = @root.join("docs/experiments/feasibility-v1/manifest.json")
    File.write(manifest_path, "changed")
    runner = ExperimentRunner.new(root: @root, client: @client)
    assert_raises(ExperimentManifest::Invalid) { runner.run!(route: "lens_only") }
    write_manifest
    @manifest["cases"].first["zip"] = "00000"
    write_manifest
    assert_raises(LocationResolver::UnmappedZip) { runner.run!(route: "lens_only") }
    @manifest["cases"].first["zip"] = "10001"
    relative = @manifest["artifacts"].keys.first
    File.write(@root.join(relative), "bad")
    @manifest["artifacts"][relative] = { "bytes" => 3, "sha256" => Digest::SHA256.hexdigest("bad") }
    write_manifest
    assert_raises(PhotoValidator::Invalid) { runner.run!(route: "lens_only") }
    File.binwrite(@root.join(relative), @photo)
    @manifest["artifacts"][relative] = { "bytes" => @photo.bytesize, "sha256" => Digest::SHA256.hexdigest(@photo) }
    write_manifest
    FileUtils.remove_dir(@path.dirname)
    assert_raises(ExperimentLedger::Error) { runner.run!(route: "lens_only") }
    assert_empty @calls
  end

  test "missing account check blocks upload and a real fixture flow needs judgment before next case" do
    runner = ExperimentRunner.new(root: @root, client: @client)
    assert_raises(ExperimentLedger::Error) { runner.run!(route: "lens_only") }
    assert_empty @calls
    runner.initialize_ledger!
    summary = runner.account!
    assert_equal 20, summary["total_searches_left"]
    refute_match(/private|secret|account_email|api_key/, summary.to_json)
    result = runner.run!(route: "lens_only")
    assert_equal "success", result["technical_status"]
    assert_equal 1, result["search_attempts"]
    assert_equal [ "/account.json", "/image", "/search.json" ], @calls
    assert_raises(ExperimentLedger::Error) { runner.run!(route: "lens_only") }
    assert runner.score!(route: "lens_only", case_id: IDS.first, judgment: judgment)["passed"]
    assert_equal 1, runner.report["search_attempts"]
    evidence = File.read(@root.join("docs/experiments/feasibility-v1/live-evidence.json"))
    refute_match(/offline-secret-key|private-upload-reference|api_key|account_email/, evidence)
  end
  test "explicit offline initialization refuses existing ledger or evidence" do
    runner = ExperimentRunner.new(root: @root, client: @client)
    assert_raises(ExperimentLedger::Error) { runner.account! }
    runner.initialize_ledger!
    assert_raises(ExperimentLedger::Error) { runner.initialize_ledger! }
    File.delete(@path)
    File.write(@root.join("docs/experiments/feasibility-v1/live-evidence.json"), "{}")
    assert_raises(ExperimentLedger::Error) { runner.initialize_ledger! }
    refute File.exist?(@path)
    assert_empty @calls
  end
end

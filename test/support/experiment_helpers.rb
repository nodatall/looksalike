require "tmpdir"
require "fileutils"
require "digest"

module ExperimentHelpers
  IDS = %w[ornate-sofa modern-sofa dining-chair wood-table dresser].freeze

  def prepare_experiment
    @temporary = File.realpath(Dir.mktmpdir("looksalike-offline-test-"))
    @root = Pathname(@temporary)
    @path = @root.join("storage/feasibility-v1.sqlite3")
    FileUtils.mkdir_p(@path.dirname)
    folder = @root.join("docs/experiments/feasibility-v1")
    FileUtils.mkdir_p(folder)
    @photo = Vips::Image.black(24, 16, bands: 3).write_to_buffer(".jpg")
    File.binwrite(folder.join("fixture.jpg"), @photo)
    relative = "docs/experiments/feasibility-v1/fixture.jpg"
    @manifest = { "status" => "offline_test_fixture", "artifacts" => { relative => { "bytes" => @photo.bytesize, "sha256" => Digest::SHA256.hexdigest(@photo) } },
      "cases" => IDS.zip(%w[10001 94103 60601 02108 98101]).map { |id, zip| { "id" => id, "zip" => zip, "location" => LocationResolver.resolve(zip).to_h.transform_keys(&:to_s), "photo" => { "path" => relative, "width" => 24, "height" => 16 } } } }
    write_manifest
    @calls = []
    @client = SerpApi::Client.new(api_key: "offline-secret-key", transport: ->(uri:, **) do
      @calls << uri.path
      if uri.path == "/image"
        [ 200, '{"image_id":"private-upload-reference"}' ]
      elsif uri.path == "/account.json"
        [ 200, '{"account_status":"Active","total_searches_left":20,"api_key":"offline-secret-key","account_email":"private@example.com"}' ]
      else
        [ 200, { "search_metadata" => { "status" => "Success", "json_endpoint" => "https://private.example/?api_key=secret" }, "related_content" => [ { "query" => "Oak chairs" } ], "visual_matches" => candidates, "images_results" => candidates }.to_json ]
      end
    end)
  end

  def write_manifest
    folder = @root.join("docs/experiments/feasibility-v1")
    bytes = JSON.pretty_generate(@manifest)
    File.write(folder.join("manifest.json"), bytes)
    @checksum = Digest::SHA256.hexdigest(bytes)
    File.write(folder.join("manifest.sha256"), @checksum + "\n")
  end

  def store(clock: -> { Time.now.utc })
    ExperimentLedger.new(path: @path, expected_path: @path, manifest_checksum: @checksum, case_ids: IDS, create: !File.exist?(@path), clock: clock)
  end

  def with_store
    ledger = store
    yield ledger
  ensure
    ledger&.close
  end

  def allowance(ledger)
    ledger.record_account!({ "account_status" => "Active", "total_searches_left" => 100 })
  end

  def candidates
    (1..3).map { |id| { "title" => "Oak chair", "link" => "https://newyork.craigslist.org/fuo/#{id}.html", "thumbnail" => "https://encrypted-tbn0.gstatic.com/images?q=chair" } }
  end

  def outcome(count: 3, elapsed_ms: 1000)
    { "status" => "success", "elapsed_ms" => elapsed_ms, "listings" => candidates.first(count) }
  end

  def judgment(count: 3, pass: true)
    { "reason" => "Offline fixture judgment", "cards" => (1..count).map { |position| { "position" => position, "reason" => "Offline fixture observations" }.merge(ExperimentLedger::CARD_FLAGS.to_h { |flag| [ flag, pass ] }) } }
  end
end

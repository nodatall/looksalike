#!/usr/bin/env ruby
# Disposable manual experiment. Default preflight is offline and read-only.
require_relative 'ebay-v1'

module EbayFlowV3
  NAME = 'ebay-flow-v3'
  TABLES = %w[identity cases attempts account_checks diagnostic_v1_attempts query_v2_attempts ebay_v1_attempts ebay_us_v1_attempts ebay_us_retry_v1_attempts ebay_no_country_v1_attempts ebay_flow_v1_cases ebay_flow_v1_attempts ebay_flow_v1_accounts ebay_flow_v2_cases ebay_flow_v2_attempts ebay_flow_v2_accounts].freeze
  CASE_TABLE = 'ebay_flow_v3_cases'
  ATTEMPT_TABLE = 'ebay_flow_v3_attempts'
  ACCOUNT_TABLE = 'ebay_flow_v3_accounts'
  STAGES = %w[upload lens vision ebay].freeze
  VISUAL_EXPECTATIONS = {
    'ornate-sofa' => 'Curved carved dark wood exposed frame, patterned upholstered seat and back.',
    'modern-sofa' => 'Green velvet sofa, straight arms, two back cushions, raised wood legs.',
    'dining-chair' => 'Brown wood ladder-back chair, turned front legs, short curved supports.',
    'wood-table' => 'White rectangular farmhouse storage coffee table with sliding barn doors.',
    'dresser' => 'Low wide pale gray or white eight-drawer modern dresser, flat fronts and recessed handles.'
  }.freeze
  SOURCES = %w[agent-scratch/ebay-flow-v3.rb agent-scratch/ebay-flow-v3-offline.rb agent-scratch/ebay-v1.rb agent-scratch/query-v2.rb agent-scratch/diagnostic-v1.rb docs/experiments/query-v3/search_query_v2.rb app/models/search_query.rb app/services/photo_validator.rb app/services/search_deadline.rb app/services/serp_api/client.rb app/services/serp_api/http_transport.rb app/models/photo_query.rb app/services/ebay_query_preparation.rb app/services/vision/client.rb app/services/vision/http_transport.rb agent-scratch/ebay-flow-v2.rb agent-scratch/ebay-flow-v2-offline.rb].freeze

  class Client < SerpApi::Client
    def ebay(params:, deadline:) = send(:search, params, deadline)
  end

  # Probe-only transport records bounded diagnostic fields, never response text or images.
  class VisionDiagnosticTransport
    attr_reader :diagnostics
    def call(uri:, request:, deadline:, max_bytes:)
      @diagnostics = {}
      deadline.within do
        http = Net::HTTP.new(uri.host, uri.port, nil)
        http.use_ssl = true
        http.max_retries = 0
        http.open_timeout = http.read_timeout = http.write_timeout = deadline.remaining
        request['Accept'] = 'application/json'
        request['Accept-Encoding'] = 'identity'
        body = +''.b
        status = nil
        http.start do |connection|
          connection.request(request) do |response|
            status = response.code.to_i
            @diagnostics['http_status'] = status
            length = response['Content-Length']
            raise Vision::Client::Error.new(:invalid_response) if length && length.to_i > max_bytes
            response.read_body do |chunk|
              deadline.remaining
              raise Vision::Client::Error.new(:invalid_response) if body.bytesize + chunk.bytesize > max_bytes
              body << chunk
              http.read_timeout = deadline.remaining
            end
          end
        end
        capture(body)
        [status, body]
      end
    end

    def capture(body)
      data = JSON.parse(body)
      return unless data.is_a?(Hash)
      safe = ->(value) { value if value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_.:-]{1,100}\z/) }
      @diagnostics['model'] = safe.call(data['model'])
      choice = data['choices'].is_a?(Array) ? data['choices'].first : nil
      @diagnostics['finish_reason'] = safe.call(choice['finish_reason']) if choice.is_a?(Hash)
      if data['error'].is_a?(Hash)
        @diagnostics['error_code'] = safe.call(data['error']['code'])
        @diagnostics['error_type'] = safe.call(data['error']['type'])
      end
      @diagnostics.compact!
    rescue JSON::ParserError
      @diagnostics['body_format'] = 'not_json'
    end
  end

  def self.digest(path) = Digest::SHA256.file(path).hexdigest
  def self.hash(value) = Digest::SHA256.hexdigest(JSON.generate(value))
  def self.write(path, value) = File.write(path, JSON.pretty_generate(value) + "\n", mode: 'wx', perm: 0o600)

  class Runner
    def initialize(root: Rails.root, ledger: nil, directory: nil, client: nil, vision_client: nil)
      @root = Pathname(root).realpath
      @ledger = ledger || @root.join('storage/feasibility-v1.sqlite3')
      @dir = Pathname(directory || @root.join('docs/experiments', NAME))
      @client = client
      @vision_client = vision_client
      @vision_transport = VisionDiagnosticTransport.new
    end

    def db(writable: false)
      raise 'Existing ledger required' unless File.file?(@ledger)
      connection = SQLite3::Database.new(@ledger.to_s, readonly: !writable)
      connection.results_as_hash = true
      connection.busy_timeout = 5000
      connection
    end

    def rows(connection, table)
      return [] unless connection.get_first_value("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", table)
      connection.execute("SELECT * FROM #{table} ORDER BY rowid")
    end

    def baseline(connection) = TABLES.to_h { |table| [table, EbayFlowV3.hash(rows(connection, table))] }

    def photos
      path = @root.join('docs/experiments/feasibility-v1/manifest.json')
      raise 'Original manifest changed' unless EbayFlowV3.digest(path) == File.read(path.dirname.join('manifest.sha256')).strip
      JSON.parse(File.read(path)).fetch('cases').map { |entry| entry.slice('id', 'order', 'photo') }
    end

    def model_catalog
      path = Pathname('/tmp/looksalike-venice-models-current.json')
      raw = JSON.parse(File.read(path))
      model = raw.fetch('data').find { |item| item['id'] == Vision::Client::MODEL }
      raise 'Vision model unavailable' unless model && model.dig('model_spec', 'offline') == false
      spec = model.fetch('model_spec')
      caps = spec.fetch('capabilities')
      raise 'Required vision capabilities unavailable' unless caps['supportsVision'] == true && caps['supportsResponseSchema'] == true
      raise 'Vision prices changed' unless spec.dig('pricing', 'input', 'usd') == 0.21 && spec.dig('pricing', 'output', 'usd') == 1.9
      {id: model.fetch('id'), context_length: model.fetch('context_length'), max_completion_tokens: spec.fetch('maxCompletionTokens'),
       supports_vision: true, supports_response_schema: true, offline: false,
       input_usd_per_million_tokens: 0.21, output_usd_per_million_tokens: 1.9,
       catalog_sha256: EbayFlowV3.digest(path), catalog_file_checked_at: File.mtime(path).utc.iso8601}
    end

    def verify_photos
      photos.each do |entry|
        spec = entry.fetch('photo')
        path = @root.join(spec.fetch('path'))
        raise 'Photo changed' unless File.size(path) == spec.fetch('bytes') && EbayFlowV3.digest(path) == spec.fetch('sha256')
        photo = PhotoValidator.call(File.binread(path), deadline: SearchDeadline.new)
        raise 'Photo dimensions changed' unless [photo.width, photo.height, photo.content_type] == spec.values_at('width', 'height', 'content_type')
      end
    end

    def historical_count(connection)
      base = rows(connection, 'attempts').count { |r| r['stage'] != 'upload' }
      base + TABLES.grep(/_attempts\z/).sum { |table| rows(connection, table).count { |r| r['stage'] != 'upload' } }
    end

    def manifest(connection)
      path = @dir.join('manifest.json')
      sha = EbayFlowV3.digest(path)
      raise 'Manifest changed' unless sha == File.read(@dir.join('manifest.sha256')).strip
      data = JSON.parse(File.read(path))
      raise 'Prior evidence changed' unless data.fetch('prior_tables') == baseline(connection)
      data.fetch('files').each { |file, hash| raise "Frozen file changed: #{file}" unless EbayFlowV3.digest(@root.join(file)) == hash }
      raise 'Photo cases changed' unless data.fetch('cases') == photos
      [data, sha]
    end

    def preflight
      connection = db
      raise 'Expected twenty-nine historical search attempts' unless historical_count(connection) == 29
      verify_photos
      frozen = @dir.join('manifest.json').exist?
      manifest(connection) if frozen
      cases = rows(connection, CASE_TABLE)
      attempts = rows(connection, ATTEMPT_TABLE)
      {status: 'offline_preflight_passed', frozen: frozen, historical_searches: 29, cases: photos.map { |x| x.fetch('id') },
       new_searches: attempts.count { |r| %w[lens ebay images].include?(r['stage']) }, uploads: attempts.count { |r| r['stage'] == 'upload' },
       vision_attempts: attempts.count { |r| r['stage'] == 'vision' },
       vision_reserved_usd: (attempts.count { |r| r['stage'] == 'vision' } * 3) / 100.0,
       completed_cases: cases.count { |r| r['outcome'] }, scored_cases: cases.count { |r| r['judgment'] },
       incomplete_reservations: attempts.count { |r| r['outcome'].nil? }, searches_dispatched: 0}
    ensure
      connection&.close
    end

    def freeze!
      preflight
      raise 'Experiment already prepared' if @dir.exist?
      connection = db(writable: true)
      raise 'Experiment tables already exist' if connection.get_first_value("SELECT 1 FROM sqlite_master WHERE name LIKE 'ebay_flow_v3_%'")
      files = (SOURCES + Dir.glob(@root.join('docs/experiments/**/*').to_s).select { |p| File.file?(p) && !p.include?('/photos/') }.map { |p| Pathname(p).relative_path_from(@root).to_s }).uniq
      catalog = model_catalog
      raise 'Catalog check expired' unless (Time.now.utc - Time.iso8601(catalog.fetch(:catalog_file_checked_at))).between?(0, 3600)
      data = {model_catalog: catalog, experiment: NAME, frozen_at: Time.now.utc.iso8601, cases: photos,
        reference_visual_expectations: VISUAL_EXPECTATIONS,
        requests: {
          upload: {method: 'POST', endpoint: 'https://serpapi.com/image', image: 'validated prepared photo bytes'},
          lens: {method: 'GET', endpoint: 'https://serpapi.com/search.json', parameters: {engine: 'google_lens', type: 'all', country: 'us', hl: 'en'}, runtime: 'Private image_id from this upload; never recorded'},
          vision: {method: 'POST', endpoint: Vision::Client::ENDPOINT, policy: Vision::Client.metadata, runtime: 'Validated JPEG inline; only when PhotoQuery.fallback?; 15 seconds with 10 seconds reserved for eBay; no web tools'},
          ebay: {method: 'GET', endpoint: 'https://serpapi.com/search.json', parameters: {engine: 'ebay', ebay_domain: 'ebay.com', _ipg: '25'}, runtime: '_nkw is unchanged EbayQueryPreparation.query; no ZIP, pickup or country filter'}
        },
        budget: {searches: 10, uploads: 5, vision_attempts: 5, vision_reserved_usd_per_attempt: 0.03, vision_reserved_usd_total: 0.15, historical_searches: 29, retries: 0}, deadline_seconds: 55,
        criterion: 'At least 3 of first 6 distinct eligible items relevant and accessible, in 4 of 5 cases. Same category and similar shape, material or style. Stop after 2 failures. No replacement or reranking.',
        stages: STAGES, country: 'Accept only explicit Located in United States response field; no request country filter.',
        query_version: SearchQuery::VERSION, prior_tables: baseline(connection), files: files.to_h { |p| [p, EbayFlowV3.digest(@root.join(p))] }}
      FileUtils.mkdir_p(@dir)
      EbayFlowV3.write(@dir.join('manifest.json'), data)
      File.write(@dir.join('manifest.sha256'), EbayFlowV3.digest(@dir.join('manifest.json')) + "\n", mode: 'wx')
      connection.transaction(:immediate) do
        connection.execute_batch(<<~SQL)
          CREATE TABLE #{CASE_TABLE}(case_id TEXT PRIMARY KEY, manifest_sha256 TEXT NOT NULL, started_at TEXT NOT NULL, outcome TEXT, judgment TEXT);
          CREATE TABLE #{ATTEMPT_TABLE}(case_id TEXT NOT NULL, stage TEXT NOT NULL CHECK(stage IN ('upload','lens','vision','ebay')), manifest_sha256 TEXT NOT NULL, parameters TEXT NOT NULL, reserved_at TEXT NOT NULL, outcome TEXT, PRIMARY KEY(case_id,stage));
          CREATE TABLE #{ACCOUNT_TABLE}(checked_at TEXT NOT NULL, searches_at_check INTEGER NOT NULL, summary TEXT NOT NULL);
          CREATE TRIGGER ebay_flow_v3_cap BEFORE INSERT ON #{ATTEMPT_TABLE} WHEN (NEW.stage='upload' AND (SELECT COUNT(*) FROM #{ATTEMPT_TABLE} WHERE stage='upload')>=5) OR (NEW.stage IN ('lens','ebay') AND (SELECT COUNT(*) FROM #{ATTEMPT_TABLE} WHERE stage IN ('lens','ebay'))>=10) OR (NEW.stage='vision' AND (SELECT COUNT(*) FROM #{ATTEMPT_TABLE} WHERE stage='vision')>=5) BEGIN SELECT RAISE(ABORT,'Attempt cap'); END;
        SQL
        [CASE_TABLE, ATTEMPT_TABLE, ACCOUNT_TABLE].each do |table|
          connection.execute("CREATE TRIGGER #{table}_delete BEFORE DELETE ON #{table} BEGIN SELECT RAISE(ABORT,'Immutable'); END")
          columns = connection.execute("PRAGMA table_info(#{table})").map { |r| r['name'] } - %w[outcome judgment]
          connection.execute("CREATE TRIGGER #{table}_identity BEFORE UPDATE OF #{columns.join(',')} ON #{table} BEGIN SELECT RAISE(ABORT,'Immutable'); END")
          (%w[outcome judgment] - (table == CASE_TABLE ? [] : table == ATTEMPT_TABLE ? ['judgment'] : %w[outcome judgment])).each do |field|
            connection.execute("CREATE TRIGGER #{table}_#{field} BEFORE UPDATE OF #{field} ON #{table} WHEN OLD.#{field} IS NOT NULL BEGIN SELECT RAISE(ABORT,'Already recorded'); END")
          end
        end
      end
      {status: 'frozen', cases: photos.map { |x| x['id'] }}
    ensure
      connection&.close
    end

    def account!
      connection = db(writable: true)
      manifest(connection)
      count = rows(connection, ATTEMPT_TABLE).count { |r| %w[lens ebay images].include?(r['stage']) }
      summary = client.account(deadline: SearchDeadline.new)
      raise 'Insufficient account allowance' unless summary['account_status'] == 'Active' && summary['total_searches_left'].to_i >= 12 - count
      connection.execute("INSERT INTO #{ACCOUNT_TABLE}(checked_at,searches_at_check,summary) VALUES(?,?,?)", [Time.now.utc.iso8601, count, JSON.generate(summary)])
      summary
    ensure
      connection&.close
    end

    def allowance!(connection)
      account = rows(connection, ACCOUNT_TABLE).last
      raise 'Run explicit account check' unless account
      raise 'Account check expired' unless (Time.now.utc - Time.iso8601(account.fetch('checked_at'))).between?(0, 3600)
      total = rows(connection, ATTEMPT_TABLE).count { |r| %w[lens ebay images].include?(r['stage']) }
      raise 'Allowance exhausted' unless JSON.parse(account['summary']).fetch('total_searches_left') - (total - account['searches_at_check']) >= 3
    end

    def execute(id, deadline: nil)
      preflight
      connection = db(writable: true)
      _, sha = manifest(connection)
      entry = photos.find { |x| x['id'] == id }
      raise 'Unknown case' unless entry
      connection.transaction(:immediate) do
        previous = rows(connection, CASE_TABLE)
        raise 'Earlier case unscored or incomplete' unless previous.all? { |r| r['outcome'] && r['judgment'] }
        raise 'Two failures: experiment stopped' if previous.count { |r| !JSON.parse(r['judgment'])['passed'] } >= 2
        raise 'Out of order, duplicate or exhausted' unless photos[previous.size] == entry
        raise 'Incomplete attempt blocks dispatch' if rows(connection, ATTEMPT_TABLE).any? { |r| r['outcome'].nil? }
        allowance!(connection)
        connection.execute("INSERT INTO #{CASE_TABLE}(case_id,manifest_sha256,started_at) VALUES(?,?,?)", [id, sha, Time.now.utc.iso8601(6)])
      end
      began = now
      deadline ||= SearchDeadline.new
      image_id = nil
      result = {'status' => 'failed', 'parameters' => [], 'stages' => [], 'candidates' => [], 'first_six' => []}
      begin
        deadline.within do
          validated = PhotoValidator.call(File.binread(@root.join(entry.fetch('photo').fetch('path'))), deadline: deadline)
          image_id = stage(connection, id, sha, 'upload', {'photo_sha256' => entry['photo']['sha256']}, result, deadline) { client.upload(photo: validated.bytes, deadline: deadline) }
          lens_params = {'engine' => 'google_lens', 'type' => 'all', 'country' => 'us', 'hl' => 'en'}
          lens = stage(connection, id, sha, 'lens', lens_params, result, deadline) { client.lens(image_id: image_id, type: 'all', deadline: deadline) }
          result['provider_metadata'] = {'lens' => metadata(lens)}
          lens_query = SearchQuery.call(lens)
          result['lens_interpretation'] = lens_query.phrase
          vision_started = nil
          callback = lambda do |policy|
            raise 'Unexpected vision policy' unless policy == Vision::Client.metadata && policy.fetch(:reserved_usd) == '0.03'
            reserve_stage(connection, id, sha, 'vision', policy, deadline)
            vision_started = now
            result['parameters'] << policy
            true
          end
          begin
            prepared = EbayQueryPreparation.new(vision_client: vision_client).call(
              lens_response: lens, photo: validated, deadline: deadline, before_vision_dispatch: callback)
            result['query_preparation'] = {status: prepared.status, source: prepared.source, metadata: prepared.metadata}
          ensure
            result['vision_diagnostics'] = @vision_transport.diagnostics if vision_started && @vision_transport.diagnostics
            if vision_started
              observation = {'stage' => 'vision', 'status' => prepared&.status || 'failed', 'elapsed_ms' => elapsed(vision_started)}
              result['stages'] << observation
              finish_stage(connection, id, 'vision', observation)
            end
          end
          result['interpretation'] = prepared.query
          result['query_source'] = prepared.source
          result['excerpts'] = {'related_queries' => Array(lens['related_content']).first(20).filter_map { |x| x['query'] if x.is_a?(Hash) }, 'visual_match_titles' => Array(lens['visual_matches']).first(8).filter_map { |x| x['title'] if x.is_a?(Hash) }}
          if prepared.query.nil?
            result['status'] = prepared.status
          else
            params = {'engine' => 'ebay', '_nkw' => prepared.query, 'ebay_domain' => 'ebay.com', '_ipg' => '25'}
            ebay = stage(connection, id, sha, 'ebay', params, result, deadline) { client.ebay(params: params, deadline: deadline) }
            result['provider_metadata']['ebay'] = metadata(ebay)
            result['ebay_parameters_echo'] = ebay.fetch('search_parameters', {}).slice(*params.keys)
            result.merge!(normalize(ebay))
            result['status'] = 'success'
          end
          deadline.remaining
        end
      rescue StandardError => error
        result['status'] = error.is_a?(SearchDeadline::Exceeded) ? 'deadline' : 'failed'
        result['error_class'] = error.class.name
      end
      result['elapsed_ms'] = elapsed(began)
      result = clean(result, image_id)
      connection.execute("UPDATE #{CASE_TABLE} SET outcome=? WHERE case_id=? AND outcome IS NULL", [JSON.generate(result), id])
      raise 'Outcome not stored' unless connection.changes == 1
      EbayFlowV3.write(@dir.join("#{id}.json"), {case_id: id, manifest_sha256: sha, outcome: result})
      result
    ensure
      connection&.close
    end

    def reserve_stage(connection, id, sha, name, params, deadline)
      deadline.remaining
      connection.transaction(:immediate) do
        manifest(connection)
        allowance!(connection)
        previous = rows(connection, ATTEMPT_TABLE).select { |r| r['case_id'] == id }
        allowed = case name
        when 'upload' then [[]]
        when 'lens' then [%w[upload]]
        when 'vision' then [%w[upload lens]]
        when 'ebay' then [%w[upload lens], %w[upload lens vision]]
        else []
        end
        complete = previous.all? do |row|
          row['outcome'] && %w[success ready].include?(JSON.parse(row['outcome'])['status'])
        end
        raise 'Invalid stage order or uncertain prior stage' unless allowed.include?(previous.map { |r| r['stage'] }) && complete
        connection.execute("INSERT INTO #{ATTEMPT_TABLE}(case_id,stage,manifest_sha256,parameters,reserved_at) VALUES(?,?,?,?,?)", [id, name, sha, JSON.generate(params), Time.now.utc.iso8601(6)])
      end
      true
    end

    def finish_stage(connection, id, name, observation)
      connection.execute("UPDATE #{ATTEMPT_TABLE} SET outcome=? WHERE case_id=? AND stage=? AND outcome IS NULL", [JSON.generate(observation), id, name])
      raise 'Stage outcome not stored' unless connection.changes == 1
    end

    def stage(connection, id, sha, name, params, result, deadline)
      reserve_stage(connection, id, sha, name, params, deadline)
      started = now
      observation = {'stage' => name, 'status' => 'failed'}
      result['parameters'] << params
      begin
        deadline.remaining
        value = yield
        deadline.remaining
        observation['status'] = 'success'
        value
      ensure
        observation['elapsed_ms'] = elapsed(started)
        result['stages'] << observation
        finish_stage(connection, id, name, observation)
      end
    end

    def normalize(data)
      items = data.fetch('organic_results', [])
      raise 'Unexpected results' unless items.is_a?(Array) && items.size <= 100
      parsed = EbayV1.classify(200, JSON.generate(data), ->(x) { client.redact(x) })
      raise 'Provider error' unless parsed['classification'] == 'results_returned'
      counts = Hash.new(0)
      seen = {}
      candidates = []
      parsed['listings'].each do |row|
        reason = if !row['url'] then 'invalid_item_url'
        elsif !row['title'].is_a?(String) || row['title'].strip.empty? then 'missing_title'
        elsif !row['thumbnail'] then 'missing_thumbnail'
        elsif row['location'] != 'Located in United States' then 'not_explicit_us'
        elsif seen[row['url']] then 'duplicate_item'
        else 'accepted'
        end
        row['filter'] = reason
        counts[reason] += 1
        if reason == 'accepted'
          seen[row['url']] = true
          candidates << row
        end
      end
      {'returned_items' => items.size, 'counts' => counts, 'provider_rows' => parsed['listings'], 'candidates' => candidates, 'first_six' => candidates.first(6)}
    end

    def metadata(data)
      data.fetch('search_metadata', {}).slice('id', 'status', 'created_at', 'processed_at', 'total_time_taken')
    end

    def score(id, judgment)
      connection = db(writable: true)
      manifest(connection)
      record = rows(connection, CASE_TABLE).find { |r| r['case_id'] == id }
      raise 'Missing completed unscored case' unless record && record['outcome'] && !record['judgment']
      outcome = JSON.parse(record['outcome'])
      checks = judgment.fetch('items')
      raise 'Must judge original first six in order' unless checks.map { |x| x.fetch('url') } == outcome.fetch('first_six').map { |x| x['url'] }
      checks.each do |item|
        raise 'Need explicit relevance, access and notes' unless [true, false].include?(item['relevant']) && [true, false].include?(item['accessible']) && item['notes'].is_a?(String) && !item['notes'].strip.empty?
      end
      relevant = checks.count { |x| x['relevant'] && x['accessible'] }
      saved = {'items' => checks, 'relevant_accessible_count' => relevant, 'scored_at' => Time.now.utc.iso8601,
        'passed' => outcome['status'] == 'success' && outcome['elapsed_ms'] <= 55_000 && relevant >= 3}
      saved = clean(saved, nil)
      connection.execute("UPDATE #{CASE_TABLE} SET judgment=? WHERE case_id=? AND judgment IS NULL", [JSON.generate(saved), id])
      raise 'Judgment not stored' unless connection.changes == 1
      EbayFlowV3.write(@dir.join("#{id}-judgment.json"), saved)
      saved
    ensure
      connection&.close
    end

    def clean(value, image_id, field = nil)
      case value
      when Hash then value.to_h { |k, v| [k, clean(v, image_id, k)] }
      when Array then value.map { |v| clean(v, image_id, field) }
      when String
        text = client.redact(value)
        vision_key = ENV['VENICE_API_KEY'].to_s
        text = text.gsub(vision_key, '[redacted]') unless vision_key.empty?
        text = text.gsub(image_id, '[redacted]') if image_id && !image_id.empty?
        text = text.gsub(%r{https?://\S+}, '[URL omitted]') unless %w[url thumbnail].include?(field)
        text.gsub(/\b(?:api_key|access_token|client_secret)=\S+/i, '[credential omitted]').gsub(/[[:cntrl:]]/, ' ')[0, 1000]
      else value
      end
    end

    def vision_client = @vision_client ||= Vision::Client.new(transport: @vision_transport)
    def client = @client ||= Client.new
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    def elapsed(start) = ((now - start) * 1000).round(3)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    runner = EbayFlowV3::Runner.new
    result = case ARGV
    when ['--preflight'], [] then runner.preflight
    when ['--freeze'] then runner.freeze!
    when ['--account'] then runner.account!
    else
      if ARGV.length == 2 && ARGV.first == '--execute'
        runner.execute(ARGV.last)
      elsif ARGV.length == 3 && ARGV.first == '--score'
        runner.score(ARGV[1], JSON.parse(File.read(ARGV[2])))
      else
        raise 'Use --preflight, --freeze, --account, --execute CASE or --score CASE FILE'
      end
    end
    puts JSON.pretty_generate(result)
  rescue StandardError => error
    warn "Probe stopped (#{error.class.name}). Inspect reservations; no automatic retries."
    exit 1
  end
end

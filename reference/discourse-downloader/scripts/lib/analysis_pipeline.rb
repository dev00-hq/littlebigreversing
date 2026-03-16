# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'pathname'
require 'set'
require 'time'

class AnalysisPipeline
  DEFAULT_CHUNK_SIZE = 250
  DEFAULT_MAX_RECORDS = 50_000
  DEFAULT_MAX_BYTES = 50 * 1024 * 1024
  DEFAULT_MAX_ENTITIES = 25_000
  DEFAULT_INPUT_SCOPE = 'index_normalized'
  MAX_TOPIC_WINDOW_CLAIMS = 40
  STAGE_IDS = (0..5).freeze

  KEYWORDS = {
    format: %w[hqr ile obl compression offset offsets index indices entry entries checksum],
    tool: %w[tool editor extractor converter github gitlab utility],
    workflow: %w[workflow pipeline steps process import export replace modding],
    pitfall: %w[pitfall break broken crash crashes issue issues warning limitation],
    glossary: %w[holomap sendell zeelich dinofly twinsen proto-pack]
  }.freeze

  attr_reader :run_id

  def initialize(root_dir:, run_id:, stage_target:, resume:, input_scope:, max_records:, max_bytes:, max_entities:, chunk_size:)
    @root_dir = File.expand_path(root_dir)
    @run_id = run_id
    @stage_target = Integer(stage_target)
    @resume = resume
    @input_scope = input_scope
    @chunk_size = [Integer(chunk_size), 1].max

    @limits = {
      'max_records' => [Integer(max_records), 1].max,
      'max_bytes' => [Integer(max_bytes), 1].max,
      'max_entities' => [Integer(max_entities), 1].max
    }

    @corpus_dir = File.join(@root_dir, 'corpus')
    @analysis_dir = File.join(@corpus_dir, 'analysis')
    @analysis_index_dir = File.join(@analysis_dir, 'index')
    @runs_root = File.join(@root_dir, 'runs')
    @run_dir = File.join(@runs_root, @run_id)
    @manifest_path = File.join(@run_dir, 'analysis_manifest.json')

    validate!
    ensure_dirs
    initialize_manifest
  end

  def execute
    stages_to_run.each do |stage|
      next if stage_completed?(stage)

      stage_started(stage)
      send("stage_#{stage}")
      if stage_state(stage)['status'] == 'partial'
        stage_state(stage)['finished_at'] = Time.now.utc.iso8601
        save_manifest
        break
      else
        stage_completed(stage)
      end
    rescue StandardError => e
      stage_failed(stage, e)
      raise
    end

    @manifest['finished_at'] = Time.now.utc.iso8601
    save_manifest
    @manifest
  end

  private

  def validate!
    unless STAGE_IDS.include?(@stage_target)
      raise ArgumentError, "Stage must be in #{STAGE_IDS.to_a.join(', ')}"
    end

    allowed = %w[index_normalized with_raw]
    return if allowed.include?(@input_scope)

    raise ArgumentError, "input_scope must be one of: #{allowed.join(', ')}"
  end

  def ensure_dirs
    [@analysis_dir, @analysis_index_dir, @runs_root, @run_dir].each { |dir| FileUtils.mkdir_p(dir) }
  end

  def initialize_manifest
    if @resume && File.file?(@manifest_path)
      @manifest = JSON.parse(File.read(@manifest_path))
      @manifest['resumed_at'] = Time.now.utc.iso8601
      save_manifest
      return
    end

    @manifest = {
      'run_id' => @run_id,
      'input_scope' => @input_scope,
      'options' => {
        'stage_target' => @stage_target,
        'resume' => @resume,
        'chunk_size' => @chunk_size,
        'limits' => @limits
      },
      'started_at' => Time.now.utc.iso8601,
      'stages' => {}
    }

    reset_stage_outputs
    save_manifest
  end

  def reset_stage_outputs
    [
      stage1_records_path,
      stage2_claims_path,
      stage2_entities_path,
      topic_cards_path,
      stage4_raw_delta_path,
      stage4_claims_delta_path,
      stage4_entities_delta_path,
      stage2_claims_merged_path,
      stage2_entities_merged_path,
      topic_cards_merged_path
    ].each do |path|
      FileUtils.rm_f(path)
    end

    FileUtils.rm_rf(@analysis_index_dir)
    FileUtils.mkdir_p(@analysis_index_dir)

    STAGE_IDS.each do |stage|
      FileUtils.rm_f(stage_checkpoint_path(stage))
    end
  end

  def stages_to_run
    STAGE_IDS.select { |stage| stage <= @stage_target }
  end

  def stage_state(stage)
    @manifest['stages'][stage.to_s] ||= {}
  end

  def stage_completed?(stage)
    stage_state(stage)['status'] == 'completed'
  end

  def stage_started(stage)
    state = stage_state(stage)
    state['status'] = 'running'
    state['started_at'] ||= Time.now.utc.iso8601
    save_manifest
  end

  def stage_completed(stage)
    state = stage_state(stage)
    state['status'] = 'completed'
    state['finished_at'] = Time.now.utc.iso8601
    save_manifest
  end

  def stage_failed(stage, error)
    state = stage_state(stage)
    state['status'] = 'failed'
    state['finished_at'] = Time.now.utc.iso8601
    state['error'] = {
      'class' => error.class.to_s,
      'message' => error.message
    }
    save_manifest
  end

  def save_manifest
    File.write(@manifest_path, JSON.pretty_generate(@manifest))
  end

  def stage_checkpoint_path(stage)
    File.join(@run_dir, "stage#{stage}_checkpoint.json")
  end

  def load_checkpoint(stage)
    path = stage_checkpoint_path(stage)
    return {} unless File.file?(path)

    JSON.parse(File.read(path))
  end

  def write_checkpoint(stage, data)
    File.write(stage_checkpoint_path(stage), JSON.pretty_generate(data))
  end

  def stage_0
    schema_registry = {
      'version' => 1,
      'generated_at' => Time.now.utc.iso8601,
      'schemas' => {
        'analysis_record' => {
          'required' => %w[record_id record_type text metadata provenance],
          'optional' => %w[topic_id post_id]
        },
        'claim_record' => {
          'required' => %w[claim_id claim_kind claim_text entities confidence evidence_refs provenance],
          'optional' => %w[topic_id post_id]
        },
        'topic_card' => {
          'required' => %w[topic_id title labels summary key_claims tools formats workflows risks],
          'optional' => %w[metadata]
        },
        'run_manifest' => {
          'required' => %w[run_id input_scope started_at stages],
          'optional' => %w[finished_at]
        }
      }
    }

    sampling_policy = {
      'version' => 1,
      'input_scope_default' => DEFAULT_INPUT_SCOPE,
      'chunk_size' => @chunk_size,
      'limits' => @limits,
      'source_rules' => [
        {
          'patterns' => ['corpus/index/*.jsonl', 'corpus/normalized/*.jsonl'],
          'mode' => 'jsonl_stream',
          'deferred' => false,
          'max_records_per_chunk' => @chunk_size
        },
        {
          'patterns' => ['spec/*.md'],
          'mode' => 'markdown_line_stream',
          'deferred' => false,
          'max_records_per_chunk' => @chunk_size
        },
        {
          'patterns' => ['corpus/raw/topics/*.json', 'corpus/raw/posts/*.jsonl'],
          'mode' => 'windowed_topic_ids',
          'deferred' => true,
          'window_size' => 25
        }
      ]
    }

    schema_path = File.join(@run_dir, 'schema_registry.json')
    sampling_path = File.join(@run_dir, 'sampling_policy.json')

    File.write(schema_path, JSON.pretty_generate(schema_registry))
    File.write(sampling_path, JSON.pretty_generate(sampling_policy))

    stage_state(0)['outputs'] = [schema_path, sampling_path]
  end

  def stage_1
    checkpoint = load_checkpoint(1)
    cursors = checkpoint.fetch('cursors', {})
    metrics = checkpoint.fetch('metrics', {
      'records_emitted' => 0,
      'bytes_parsed' => 0,
      'chunks_flushed' => 0,
      'sources_completed' => 0,
      'limit_hit' => nil
    })

    limiter = StageLimiter.new(
      max_records: @limits['max_records'],
      max_bytes: @limits['max_bytes'],
      max_entities: @limits['max_entities'],
      records_so_far: metrics['records_emitted'],
      bytes_so_far: metrics['bytes_parsed']
    )

    sources = stage1_sources
    source_index = checkpoint.fetch('source_index', 0)

    if source_index.zero? && !@resume
      FileUtils.rm_f(stage1_records_path)
    end

    chunk = []
    next_source_index = source_index

    (source_index...sources.length).each do |source_idx|
      source = sources[source_idx]
      next_source_index = source_idx + 1
      next unless File.file?(source[:path])

      cursor = cursors.fetch(source[:path], 0).to_i
      last_line_seen = cursor
      fully_processed = true

      stream_source(source, cursor) do |row, line_no, raw_line|
        if limiter.limit_reached?
          fully_processed = false
          next :stop
        end

        record = build_analysis_record(source, row, line_no)
        chunk << record
        last_line_seen = line_no

        limiter.consume_record(raw_line.bytesize)
        metrics['records_emitted'] = limiter.records
        metrics['bytes_parsed'] = limiter.bytes

        if chunk.length >= @chunk_size
          append_jsonl(stage1_records_path, chunk)
          chunk.clear
          metrics['chunks_flushed'] += 1
          cursors[source[:path]] = line_no
          write_checkpoint(1, {
            'source_index' => source_idx,
            'cursors' => cursors,
            'metrics' => metrics
          })
        end

        next unless limiter.limit_reached?

        fully_processed = false
        :stop
      end

      cursors[source[:path]] = last_line_seen
      metrics['sources_completed'] += 1 if fully_processed
      next_source_index = source_idx unless fully_processed
      write_checkpoint(1, {
        'source_index' => next_source_index,
        'cursors' => cursors,
        'metrics' => metrics
      })

      break if limiter.limit_reached?
    end

    unless chunk.empty?
      append_jsonl(stage1_records_path, chunk)
      metrics['chunks_flushed'] += 1
    end

    metrics['limit_hit'] = limiter.limit_reached? ? limiter.reason : nil

    write_checkpoint(1, {
      'source_index' => limiter.limit_reached? ? next_source_index : sources.length,
      'cursors' => cursors,
      'metrics' => metrics,
      'completed' => !limiter.limit_reached?
    })

    stage_state(1)['status'] = 'partial' if limiter.limit_reached?
    stage_state(1)['metrics'] = metrics
    stage_state(1)['outputs'] = [stage1_records_path]
  end

  def stage_2
    checkpoint = load_checkpoint(2)
    cursor = checkpoint.fetch('cursor', 0).to_i
    metrics = checkpoint.fetch('metrics', {
      'records_processed' => 0,
      'claims_emitted' => 0,
      'entities_emitted' => 0,
      'duplicate_claims' => 0,
      'duplicate_entities' => 0,
      'chunks_flushed' => 0,
      'limit_hit' => nil
    })

    if cursor.zero? && !@resume
      FileUtils.rm_f(stage2_claims_path)
      FileUtils.rm_f(stage2_entities_path)
    end

    known_claim_ids = load_jsonl_id_set(stage2_claims_path, 'claim_id')
    known_entity_ids = load_jsonl_id_set(stage2_entities_path, 'entity_id')

    limiter = StageLimiter.new(
      max_records: @limits['max_records'],
      max_bytes: @limits['max_bytes'],
      max_entities: @limits['max_entities'],
      records_so_far: metrics['records_processed'],
      bytes_so_far: 0,
      entities_so_far: metrics['entities_emitted'] + metrics['claims_emitted']
    )

    claims_chunk = []
    entities_chunk = []

    return unless File.file?(stage1_records_path)

    last_line_seen = cursor

    stream_jsonl(stage1_records_path, cursor) do |record, line_no, raw_line|
      if limiter.limit_reached?
        next :stop
      end

      claims, entities = extract_claims_and_entities(record)

      claims.each do |claim|
        if known_claim_ids.include?(claim['claim_id'])
          metrics['duplicate_claims'] += 1
          next
        end
        next if limiter.limit_reached?

        known_claim_ids.add(claim['claim_id'])
        claims_chunk << claim
        limiter.consume_entity
        metrics['claims_emitted'] += 1
      end

      entities.each do |entity|
        if known_entity_ids.include?(entity['entity_id'])
          metrics['duplicate_entities'] += 1
          next
        end
        next if limiter.limit_reached?

        known_entity_ids.add(entity['entity_id'])
        entities_chunk << entity
        limiter.consume_entity
        metrics['entities_emitted'] += 1
      end

      limiter.consume_record(raw_line.bytesize)
      metrics['records_processed'] += 1
      last_line_seen = line_no

      if claims_chunk.length + entities_chunk.length >= @chunk_size
        append_jsonl(stage2_claims_path, claims_chunk) unless claims_chunk.empty?
        append_jsonl(stage2_entities_path, entities_chunk) unless entities_chunk.empty?
        claims_chunk.clear
        entities_chunk.clear
        metrics['chunks_flushed'] += 1
        write_checkpoint(2, {
          'cursor' => line_no,
          'metrics' => metrics
        })
      end

      next unless limiter.limit_reached?

      :stop
    end

    append_jsonl(stage2_claims_path, claims_chunk) unless claims_chunk.empty?
    append_jsonl(stage2_entities_path, entities_chunk) unless entities_chunk.empty?

    metrics['limit_hit'] = limiter.limit_reached? ? limiter.reason : nil

    write_checkpoint(2, {
      'cursor' => limiter.limit_reached? ? last_line_seen : file_line_count(stage1_records_path),
      'metrics' => metrics,
      'completed' => !limiter.limit_reached?
    })

    stage_state(2)['status'] = 'partial' if limiter.limit_reached?
    stage_state(2)['metrics'] = metrics
    stage_state(2)['outputs'] = [stage2_claims_path, stage2_entities_path]
  end

  def stage_3
    checkpoint = load_checkpoint(3)
    cursor = checkpoint.fetch('cursor', 0).to_i
    metrics = checkpoint.fetch('metrics', {
      'claims_processed' => 0,
      'topic_cards' => 0,
      'chunks_flushed' => 0
    })
    windows = checkpoint.fetch('topic_windows', {})

    titles = topic_title_map

    return unless File.file?(stage2_claims_path)

    stream_jsonl(stage2_claims_path, cursor) do |claim, line_no, _raw_line|
      topic_id = claim['topic_id']
      next if topic_id.nil?

      key = topic_id.to_s
      windows[key] ||= empty_topic_window
      window = windows[key]

      claim_kind = claim['claim_kind'].to_s
      window['claim_kinds'][claim_kind] = window['claim_kinds'].fetch(claim_kind, 0) + 1
      window['confidence_sum'] += claim['confidence'].to_f
      window['count'] += 1

      Array(claim['entities']).each do |entity|
        window['entities'][entity] = window['entities'].fetch(entity, 0) + 1
      end

      if window['claims'].length < MAX_TOPIC_WINDOW_CLAIMS
        window['claims'] << {
          'claim_id' => claim['claim_id'],
          'claim_text' => claim['claim_text'],
          'claim_kind' => claim_kind,
          'confidence' => claim['confidence']
        }
      end

      window['risks'] << claim['claim_text'] if claim_kind == 'pitfall' && window['risks'].length < 10

      metrics['claims_processed'] += 1

      if (metrics['claims_processed'] % @chunk_size).zero?
        metrics['chunks_flushed'] += 1
        write_checkpoint(3, {
          'cursor' => line_no,
          'metrics' => metrics,
          'topic_windows' => windows
        })
      end
    end

    cards = windows.keys.sort_by(&:to_i).map do |topic_key|
      build_topic_card(topic_key.to_i, windows[topic_key], titles[topic_key.to_i])
    end

    FileUtils.rm_f(topic_cards_path)
    append_jsonl(topic_cards_path, cards)

    metrics['topic_cards'] = cards.length

    write_checkpoint(3, {
      'cursor' => file_line_count(stage2_claims_path),
      'metrics' => metrics,
      'topic_windows' => windows,
      'completed' => true
    })

    stage_state(3)['metrics'] = metrics
    stage_state(3)['outputs'] = [topic_cards_path]
  end

  def stage_4
    if @input_scope != 'with_raw'
      stage_state(4)['metrics'] = {
        'skipped' => true,
        'reason' => 'input_scope does not include raw corpus'
      }
      stage_state(4)['outputs'] = []
      return
    end

    checkpoint = load_checkpoint(4)
    metrics = checkpoint.fetch('metrics', {
      'topics_processed' => 0,
      'raw_records_processed' => 0,
      'bytes_parsed' => 0,
      'raw_records_emitted' => 0,
      'claims_delta_emitted' => 0,
      'entities_delta_emitted' => 0,
      'windows_flushed' => 0,
      'limit_hit' => nil
    })

    topic_files = Dir.glob(File.join(@corpus_dir, 'raw', 'posts', '*.jsonl')).sort_by do |path|
      File.basename(path, '.jsonl').to_i
    end

    topic_cursor = checkpoint.fetch('topic_cursor', 0).to_i
    cursors = checkpoint.fetch('cursors', {})
    delta_raw_ids = load_jsonl_id_set(stage4_raw_delta_path, 'record_id')
    delta_claim_ids = load_jsonl_id_set(stage4_claims_delta_path, 'claim_id')
    delta_entity_ids = load_jsonl_id_set(stage4_entities_delta_path, 'entity_id')

    base_claim_ids = load_jsonl_id_set(stage2_claims_path, 'claim_id')
    base_entity_ids = load_jsonl_id_set(stage2_entities_path, 'entity_id')

    limiter = StageLimiter.new(
      max_records: @limits['max_records'],
      max_bytes: @limits['max_bytes'],
      max_entities: @limits['max_entities'],
      records_so_far: metrics['raw_records_processed'],
      bytes_so_far: metrics['bytes_parsed'],
      entities_so_far: metrics['claims_delta_emitted'] + metrics['entities_delta_emitted']
    )

    raw_chunk = []
    claim_chunk = []
    entity_chunk = []
    next_topic_cursor = topic_cursor

    (topic_cursor...topic_files.length).each do |idx|
      break if limiter.limit_reached?

      raw_file = topic_files[idx]
      source = {
        path: raw_file,
        format: :jsonl,
        record_type: 'raw_post',
        text_builder: lambda do |row|
          [row['raw'], row['cooked']].compact.join("\n")
        end,
        metadata_builder: lambda do |row|
          row.reject { |k, _v| %w[raw cooked].include?(k) }
        end,
        topic_field: 'topic_id',
        post_field: 'id',
        source_url_field: 'post_url'
      }

      cursor = cursors.fetch(raw_file, 0).to_i
      last_line_seen = cursor
      fully_processed = true

      stream_source(source, cursor) do |row, line_no, raw_line|
        if limiter.limit_reached?
          fully_processed = false
          next :stop
        end

        record = build_analysis_record(source, row, line_no)
        last_line_seen = line_no

        limiter.consume_record(raw_line.bytesize)
        metrics['raw_records_processed'] = limiter.records
        metrics['bytes_parsed'] = limiter.bytes

        unless delta_raw_ids.include?(record['record_id'])
          delta_raw_ids.add(record['record_id'])
          raw_chunk << record
          metrics['raw_records_emitted'] += 1
        end

        claims, entities = extract_claims_and_entities(record)

        claims.each do |claim|
          next if delta_claim_ids.include?(claim['claim_id']) || base_claim_ids.include?(claim['claim_id'])
          break if limiter.limit_reached?

          delta_claim_ids.add(claim['claim_id'])
          claim_chunk << claim
          limiter.consume_entity
          metrics['claims_delta_emitted'] += 1
        end

        entities.each do |entity|
          next if delta_entity_ids.include?(entity['entity_id']) || base_entity_ids.include?(entity['entity_id'])
          break if limiter.limit_reached?

          delta_entity_ids.add(entity['entity_id'])
          entity_chunk << entity
          limiter.consume_entity
          metrics['entities_delta_emitted'] += 1
        end

        if raw_chunk.length + claim_chunk.length + entity_chunk.length >= @chunk_size
          append_jsonl(stage4_raw_delta_path, raw_chunk) unless raw_chunk.empty?
          append_jsonl(stage4_claims_delta_path, claim_chunk) unless claim_chunk.empty?
          append_jsonl(stage4_entities_delta_path, entity_chunk) unless entity_chunk.empty?

          raw_chunk.clear
          claim_chunk.clear
          entity_chunk.clear

          metrics['windows_flushed'] += 1
          cursors[raw_file] = line_no
          write_checkpoint(4, {
            'topic_cursor' => idx,
            'cursors' => cursors,
            'metrics' => metrics
          })
        end

        next unless limiter.limit_reached?

        fully_processed = false
        :stop
      end

      cursors[raw_file] = last_line_seen
      metrics['topics_processed'] += 1 if fully_processed
      next_topic_cursor = fully_processed ? idx + 1 : idx

      write_checkpoint(4, {
        'topic_cursor' => next_topic_cursor,
        'cursors' => cursors,
        'metrics' => metrics
      })
    end

    append_jsonl(stage4_raw_delta_path, raw_chunk) unless raw_chunk.empty?
    append_jsonl(stage4_claims_delta_path, claim_chunk) unless claim_chunk.empty?
    append_jsonl(stage4_entities_delta_path, entity_chunk) unless entity_chunk.empty?

    metrics['limit_hit'] = limiter.limit_reached? ? limiter.reason : nil
    stage_state(4)['metrics'] = metrics

    if limiter.limit_reached?
      write_checkpoint(4, {
        'topic_cursor' => next_topic_cursor,
        'cursors' => cursors,
        'metrics' => metrics,
        'completed' => false
      })
      stage_state(4)['status'] = 'partial'
      stage_state(4)['outputs'] = [
        stage4_raw_delta_path,
        stage4_claims_delta_path,
        stage4_entities_delta_path
      ]
      return
    end

    merge_jsonl_unique(stage2_claims_path, stage4_claims_delta_path, stage2_claims_merged_path, 'claim_id')
    merge_jsonl_unique(stage2_entities_path, stage4_entities_delta_path, stage2_entities_merged_path, 'entity_id')
    build_topic_cards_from_claims(stage2_claims_merged_path, topic_cards_merged_path)

    write_checkpoint(4, {
      'topic_cursor' => topic_files.length,
      'cursors' => cursors,
      'metrics' => metrics,
      'completed' => true
    })

    stage_state(4)['outputs'] = [
      stage4_raw_delta_path,
      stage4_claims_delta_path,
      stage4_entities_delta_path,
      stage2_claims_merged_path,
      stage2_entities_merged_path,
      topic_cards_merged_path
    ]
  end

  def stage_5
    claims_path = canonical_claims_path
    entities_path = canonical_entities_path
    cards_path = canonical_topic_cards_path

    by_topic = Hash.new { |memo, key| memo[key] = { 'claim_ids' => [], 'entity_ids' => [], 'card' => false } }
    by_kind = Hash.new { |memo, key| memo[key] = { 'count' => 0, 'claim_ids' => [] } }
    by_entity = Hash.new { |memo, key| memo[key] = { 'count' => 0, 'topics' => Set.new } }
    confidence = {
      '0.0-0.39' => 0,
      '0.4-0.59' => 0,
      '0.6-0.79' => 0,
      '0.8-1.0' => 0
    }

    provenance_total = 0
    provenance_complete = 0
    claim_ids = Set.new

    if File.file?(claims_path)
      stream_jsonl(claims_path, 0) do |claim, _line_no, _raw_line|
        claim_id = claim['claim_id']
        claim_ids.add(claim_id) if claim_id

        topic_key = claim['topic_id'].to_i.to_s
        by_topic[topic_key]['claim_ids'] << claim_id if claim_id

        kind = claim['claim_kind'].to_s
        by_kind[kind]['count'] += 1
        by_kind[kind]['claim_ids'] << claim_id if claim_id && by_kind[kind]['claim_ids'].length < 500

        Array(claim['entities']).each do |entity|
          entry = by_entity[entity]
          entry['count'] += 1
          entry['topics'].add(topic_key)
        end

        bucket = confidence_bucket(claim['confidence'].to_f)
        confidence[bucket] += 1

        provenance_total += 1
        provenance_complete += 1 if provenance_complete?(claim['provenance'])
      end
    end

    if File.file?(entities_path)
      stream_jsonl(entities_path, 0) do |entity, _line_no, _raw_line|
        topic_key = entity['topic_id'].to_i.to_s
        entity_id = entity['entity_id']
        by_topic[topic_key]['entity_ids'] << entity_id if entity_id
      end
    end

    if File.file?(cards_path)
      stream_jsonl(cards_path, 0) do |card, _line_no, _raw_line|
        by_topic[card['topic_id'].to_i.to_s]['card'] = true
      end
    end

    by_entity_serialized = by_entity.transform_values do |entry|
      {
        'count' => entry['count'],
        'topics' => entry['topics'].to_a.sort
      }
    end

    File.write(File.join(@analysis_index_dir, 'by_topic_id.json'), JSON.pretty_generate(sort_hash(by_topic)))
    File.write(File.join(@analysis_index_dir, 'by_kind.json'), JSON.pretty_generate(sort_hash(by_kind)))
    File.write(File.join(@analysis_index_dir, 'by_entity.json'), JSON.pretty_generate(sort_hash(by_entity_serialized)))
    File.write(File.join(@analysis_index_dir, 'confidence_distribution.json'), JSON.pretty_generate(confidence))

    duplicate_claims = stage_state(2).dig('metrics', 'duplicate_claims').to_i
    total_claims = by_kind.values.sum { |entry| entry['count'].to_i }
    duplicate_ratio = total_claims.zero? ? 0.0 : (duplicate_claims.to_f / total_claims).round(4)

    drift = build_drift_report(claim_ids)

    quality_report = {
      'run_id' => @run_id,
      'generated_at' => Time.now.utc.iso8601,
      'coverage' => {
        'stage1_records' => file_line_count(stage1_records_path),
        'claims' => total_claims,
        'entities' => file_line_count(entities_path),
        'topic_cards' => file_line_count(cards_path)
      },
      'duplicate_claim_ratio' => duplicate_ratio,
      'provenance_completeness' => {
        'total' => provenance_total,
        'complete' => provenance_complete,
        'ratio' => provenance_total.zero? ? 0.0 : (provenance_complete.to_f / provenance_total).round(4)
      },
      'confidence_distribution' => confidence,
      'drift' => drift
    }

    quality_path = File.join(@run_dir, 'quality_report.json')
    File.write(quality_path, JSON.pretty_generate(quality_report))

    snapshot_path = File.join(@run_dir, 'canonical_claim_ids.txt')
    File.write(snapshot_path, claim_ids.to_a.sort.join("\n") + "\n")

    stage_state(5)['metrics'] = quality_report
    stage_state(5)['outputs'] = [
      File.join(@analysis_index_dir, 'by_topic_id.json'),
      File.join(@analysis_index_dir, 'by_kind.json'),
      File.join(@analysis_index_dir, 'by_entity.json'),
      File.join(@analysis_index_dir, 'confidence_distribution.json'),
      quality_path,
      snapshot_path
    ]
  end

  def stage1_sources
    [
      {
        path: File.join(@corpus_dir, 'index', 'topics_discovered.jsonl'),
        format: :jsonl,
        record_type: 'topic_discovery',
        text_builder: lambda do |row|
          [row['title'], row['excerpt']].compact.join("\n")
        end,
        metadata_builder: lambda do |row|
          row.reject { |k, _v| %w[title excerpt].include?(k) }
        end,
        topic_field: 'topic_id',
        post_field: nil,
        source_url_field: 'topic_url'
      },
      {
        path: File.join(@corpus_dir, 'index', 'topic_classification.jsonl'),
        format: :jsonl,
        record_type: 'topic_classification',
        text_builder: lambda do |row|
          [row['title'], row['first_post_preview']].compact.join("\n")
        end,
        metadata_builder: lambda do |row|
          row.reject { |k, _v| %w[title first_post_preview].include?(k) }
        end,
        topic_field: 'topic_id',
        post_field: nil,
        source_url_field: 'topic_url'
      },
      {
        path: File.join(@corpus_dir, 'index', 'evidence_index.jsonl'),
        format: :jsonl,
        record_type: 'evidence_index',
        text_builder: lambda do |row|
          [row['excerpt'], Array(row['matched_terms']).join(', ')].compact.join("\n")
        end,
        metadata_builder: lambda do |row|
          row.reject { |k, _v| %w[excerpt].include?(k) }
        end,
        topic_field: 'topic_id',
        post_field: 'post_id',
        source_url_field: 'source_url'
      },
      {
        path: File.join(@corpus_dir, 'normalized', 'topics_lba2.jsonl'),
        format: :jsonl,
        record_type: 'normalized_topic',
        text_builder: lambda do |row|
          [row['title'], row['slug']].compact.join("\n")
        end,
        metadata_builder: lambda do |row|
          row.reject { |k, _v| %w[title slug].include?(k) }
        end,
        topic_field: 'topic_id',
        post_field: nil,
        source_url_field: 'topic_url'
      },
      {
        path: File.join(@corpus_dir, 'normalized', 'posts_lba2.jsonl'),
        format: :jsonl,
        record_type: 'normalized_post',
        text_builder: lambda do |row|
          [row['raw'], row['cooked']].compact.join("\n")
        end,
        metadata_builder: lambda do |row|
          row.reject { |k, _v| %w[raw cooked].include?(k) }
        end,
        topic_field: 'topic_id',
        post_field: 'post_id',
        source_url_field: 'post_url'
      },
      {
        path: File.join(@root_dir, 'spec', 'formats.md'),
        format: :markdown,
        record_type: 'spec_formats',
        topic_field: nil,
        post_field: nil,
        source_url_field: nil
      },
      {
        path: File.join(@root_dir, 'spec', 'tools.md'),
        format: :markdown,
        record_type: 'spec_tools',
        topic_field: nil,
        post_field: nil,
        source_url_field: nil
      },
      {
        path: File.join(@root_dir, 'spec', 'workflows.md'),
        format: :markdown,
        record_type: 'spec_workflows',
        topic_field: nil,
        post_field: nil,
        source_url_field: nil
      },
      {
        path: File.join(@root_dir, 'spec', 'glossary.md'),
        format: :markdown,
        record_type: 'spec_glossary',
        topic_field: nil,
        post_field: nil,
        source_url_field: nil
      }
    ]
  end

  def stream_source(source, cursor)
    case source[:format]
    when :jsonl
      stream_jsonl(source[:path], cursor) do |row, line_no, raw_line|
        yield(row, line_no, raw_line)
      end
    when :markdown
      stream_markdown(source[:path], cursor) do |row, line_no, raw_line|
        yield(row, line_no, raw_line)
      end
    else
      raise "Unsupported format: #{source[:format]}"
    end
  end

  def stream_jsonl(path, cursor)
    line_no = 0
    File.foreach(path) do |raw_line|
      line_no += 1
      next if line_no <= cursor

      stripped = raw_line.strip
      next if stripped.empty?

      row = JSON.parse(stripped)
      result = yield(row, line_no, raw_line)
      break if result == :stop
    end
  end

  def stream_markdown(path, cursor)
    line_no = 0
    File.foreach(path) do |raw_line|
      line_no += 1
      next if line_no <= cursor

      text = raw_line.to_s.rstrip
      next if text.empty?

      row = {
        'text' => text
      }
      result = yield(row, line_no, raw_line)
      break if result == :stop
    end
  end

  def build_analysis_record(source, row, line_no)
    text = if source[:format] == :markdown
             row['text'].to_s
           else
             source[:text_builder].call(row).to_s
           end

    metadata = if source[:format] == :markdown
                 { 'line' => row['text'] }
               else
                 source[:metadata_builder].call(row)
               end

    topic_id = source[:topic_field] ? row[source[:topic_field]] : nil
    post_id = source[:post_field] ? row[source[:post_field]] : nil
    source_url = source[:source_url_field] ? row[source[:source_url_field]] : nil

    source_file = relative_path(source[:path])
    record_id = stable_hash([
      source[:record_type],
      source_file,
      line_no,
      topic_id,
      post_id,
      text
    ])

    {
      'record_id' => record_id,
      'record_type' => source[:record_type],
      'topic_id' => topic_id,
      'post_id' => post_id,
      'text' => text,
      'metadata' => metadata,
      'provenance' => {
        'source_file' => source_file,
        'line_no' => line_no,
        'source_url' => source_url
      }
    }
  end

  def extract_claims_and_entities(record)
    text = [record['text'], JSON.generate(record['metadata'])].join("\n").downcase
    claims = []
    entities = []

    KEYWORDS.each do |kind, terms|
      matched_terms = terms.select { |term| term_in_text?(text, term) }
      next if matched_terms.empty?

      confidence = [0.35 + (matched_terms.length * 0.12), 0.98].min.round(2)

      claim_text = "#{kind} references: #{matched_terms.sort.join(', ')}"
      claim_id = stable_hash([
        claim_text.downcase,
        record.dig('provenance', 'source_file'),
        record.dig('provenance', 'line_no'),
        record['topic_id'],
        record['post_id']
      ])

      claims << {
        'claim_id' => claim_id,
        'claim_kind' => kind.to_s,
        'claim_text' => claim_text,
        'entities' => matched_terms.sort,
        'confidence' => confidence,
        'evidence_refs' => [record['record_id']],
        'topic_id' => record['topic_id'],
        'post_id' => record['post_id'],
        'provenance' => record['provenance']
      }

      matched_terms.each do |entity|
        entity_id = stable_hash([
          kind,
          entity,
          record.dig('provenance', 'source_file'),
          record.dig('provenance', 'line_no'),
          record['topic_id'],
          record['post_id']
        ])

        entities << {
          'entity_id' => entity_id,
          'entity' => entity,
          'entity_kind' => kind.to_s,
          'topic_id' => record['topic_id'],
          'post_id' => record['post_id'],
          'confidence' => confidence,
          'evidence_ref' => record['record_id'],
          'provenance' => record['provenance']
        }
      end
    end

    [claims, entities]
  end

  def build_topic_cards_from_claims(claims_path, out_path)
    titles = topic_title_map
    windows = {}

    return unless File.file?(claims_path)

    stream_jsonl(claims_path, 0) do |claim, _line_no, _raw_line|
      topic_id = claim['topic_id']
      next if topic_id.nil?

      key = topic_id.to_s
      windows[key] ||= empty_topic_window
      window = windows[key]

      claim_kind = claim['claim_kind'].to_s
      window['claim_kinds'][claim_kind] = window['claim_kinds'].fetch(claim_kind, 0) + 1
      window['confidence_sum'] += claim['confidence'].to_f
      window['count'] += 1

      Array(claim['entities']).each do |entity|
        window['entities'][entity] = window['entities'].fetch(entity, 0) + 1
      end

      if window['claims'].length < MAX_TOPIC_WINDOW_CLAIMS
        window['claims'] << {
          'claim_id' => claim['claim_id'],
          'claim_text' => claim['claim_text'],
          'claim_kind' => claim_kind,
          'confidence' => claim['confidence']
        }
      end

      window['risks'] << claim['claim_text'] if claim_kind == 'pitfall' && window['risks'].length < 10
    end

    cards = windows.keys.sort_by(&:to_i).map do |topic_key|
      build_topic_card(topic_key.to_i, windows[topic_key], titles[topic_key.to_i])
    end

    FileUtils.rm_f(out_path)
    append_jsonl(out_path, cards)
  end

  def build_topic_card(topic_id, window, title)
    claim_kinds = window['claim_kinds'].sort_by { |kind, count| [-count, kind] }
    key_claims = window['claims']
      .sort_by { |entry| [-entry['confidence'].to_f, entry['claim_id'].to_s] }
      .first(8)

    top_entities = window['entities'].sort_by { |entity, count| [-count, entity] }.map(&:first)
    tools = top_entities.select { |entity| KEYWORDS[:tool].include?(entity) }.first(12)
    formats = top_entities.select { |entity| KEYWORDS[:format].include?(entity) }.first(12)
    workflows = top_entities.select { |entity| KEYWORDS[:workflow].include?(entity) }.first(12)

    avg_confidence = if window['count'].zero?
                       0.0
                     else
                       (window['confidence_sum'] / window['count']).round(3)
                     end

    {
      'topic_id' => topic_id,
      'title' => title || "Topic #{topic_id}",
      'labels' => claim_kinds.map(&:first).first(5),
      'summary' => "#{window['count']} claims, avg confidence #{avg_confidence}",
      'key_claims' => key_claims,
      'tools' => tools,
      'formats' => formats,
      'workflows' => workflows,
      'risks' => window['risks'].uniq.first(10),
      'metadata' => {
        'claim_kind_counts' => claim_kinds.to_h,
        'entity_count' => window['entities'].length
      }
    }
  end

  def empty_topic_window
    {
      'claim_kinds' => {},
      'entities' => {},
      'claims' => [],
      'risks' => [],
      'confidence_sum' => 0.0,
      'count' => 0
    }
  end

  def topic_title_map
    map = {}
    path = File.join(@corpus_dir, 'normalized', 'topics_lba2.jsonl')
    return map unless File.file?(path)

    stream_jsonl(path, 0) do |row, _line_no, _raw_line|
      topic_id = row['topic_id']
      title = row['title']
      map[topic_id.to_i] = title if topic_id && title
    end

    map
  end

  def merge_jsonl_unique(base_path, delta_path, out_path, id_key)
    seen = Set.new

    FileUtils.rm_f(out_path)

    [base_path, delta_path].each do |path|
      next unless File.file?(path)

      chunk = []
      stream_jsonl(path, 0) do |row, _line_no, _raw_line|
        id = row[id_key]
        next if id.nil? || seen.include?(id)

        seen.add(id)
        chunk << row

        if chunk.length >= @chunk_size
          append_jsonl(out_path, chunk)
          chunk.clear
        end
      end
      append_jsonl(out_path, chunk) unless chunk.empty?
    end
  end

  def build_drift_report(current_claim_ids)
    previous_path = previous_claim_snapshot
    return { 'has_previous' => false } unless previous_path

    previous_ids = Set.new
    File.foreach(previous_path) do |line|
      id = line.strip
      previous_ids.add(id) unless id.empty?
    end

    added = current_claim_ids - previous_ids
    removed = previous_ids - current_claim_ids

    {
      'has_previous' => true,
      'previous_snapshot' => relative_path(previous_path),
      'added' => added.length,
      'removed' => removed.length,
      'unchanged' => (current_claim_ids & previous_ids).length
    }
  end

  def previous_claim_snapshot
    run_dirs = Dir.glob(File.join(@runs_root, '*')).select { |path| File.directory?(path) }.sort

    run_dirs.reverse_each do |run_path|
      next if File.expand_path(run_path) == File.expand_path(@run_dir)

      snapshot = File.join(run_path, 'canonical_claim_ids.txt')
      return snapshot if File.file?(snapshot)
    end

    nil
  end

  def provenance_complete?(provenance)
    provenance.is_a?(Hash) && !provenance['source_file'].to_s.empty? && provenance['line_no'].to_i.positive?
  end

  def confidence_bucket(value)
    return '0.0-0.39' if value < 0.4
    return '0.4-0.59' if value < 0.6
    return '0.6-0.79' if value < 0.8

    '0.8-1.0'
  end

  def sort_hash(hash)
    hash.keys.sort.each_with_object({}) do |key, memo|
      memo[key] = hash[key]
    end
  end

  def append_jsonl(path, rows)
    return if rows.nil? || rows.empty?

    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'a') do |file|
      rows.each { |row| file.puts(JSON.generate(row)) }
    end
  end

  def load_jsonl_id_set(path, key)
    ids = Set.new
    return ids unless File.file?(path)

    stream_jsonl(path, 0) do |row, _line_no, _raw_line|
      value = row[key]
      ids.add(value) if value
    end
    ids
  end

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(@root_dir)).to_s
  rescue StandardError
    path
  end

  def stable_hash(parts)
    Digest::SHA256.hexdigest(parts.map { |part| part.to_s.strip }.join('|'))
  end

  def term_in_text?(text, term)
    escaped = Regexp.escape(term.downcase).gsub('\\ ', '\\s+')
    pattern = /(?<![[:alnum:]])#{escaped}(?![[:alnum:]])/
    !text.match(pattern).nil?
  end

  def file_line_count(path)
    return 0 unless File.file?(path)

    count = 0
    File.foreach(path) { |_line| count += 1 }
    count
  end

  def canonical_claims_path
    File.file?(stage2_claims_merged_path) ? stage2_claims_merged_path : stage2_claims_path
  end

  def canonical_entities_path
    File.file?(stage2_entities_merged_path) ? stage2_entities_merged_path : stage2_entities_path
  end

  def canonical_topic_cards_path
    File.file?(topic_cards_merged_path) ? topic_cards_merged_path : topic_cards_path
  end

  def stage1_records_path
    File.join(@analysis_dir, 'stage1_records.jsonl')
  end

  def stage2_claims_path
    File.join(@analysis_dir, 'stage2_claims.jsonl')
  end

  def stage2_entities_path
    File.join(@analysis_dir, 'stage2_entities.jsonl')
  end

  def topic_cards_path
    File.join(@analysis_dir, 'topic_cards.jsonl')
  end

  def stage4_raw_delta_path
    File.join(@analysis_dir, 'stage4_raw_delta.jsonl')
  end

  def stage4_claims_delta_path
    File.join(@analysis_dir, 'stage4_claims_delta.jsonl')
  end

  def stage4_entities_delta_path
    File.join(@analysis_dir, 'stage4_entities_delta.jsonl')
  end

  def stage2_claims_merged_path
    File.join(@analysis_dir, 'stage2_claims_merged.jsonl')
  end

  def stage2_entities_merged_path
    File.join(@analysis_dir, 'stage2_entities_merged.jsonl')
  end

  def topic_cards_merged_path
    File.join(@analysis_dir, 'topic_cards_merged.jsonl')
  end

  class StageLimiter
    attr_reader :records, :bytes, :entities, :reason

    def initialize(max_records:, max_bytes:, max_entities:, records_so_far: 0, bytes_so_far: 0, entities_so_far: 0)
      @max_records = max_records
      @max_bytes = max_bytes
      @max_entities = max_entities
      @records = records_so_far.to_i
      @bytes = bytes_so_far.to_i
      @entities = entities_so_far.to_i
      @reason = nil
    end

    def consume_record(byte_size)
      @records += 1
      @bytes += byte_size.to_i
      evaluate
    end

    def consume_entity
      @entities += 1
      evaluate
    end

    def limit_reached?
      !@reason.nil?
    end

    private

    def evaluate
      @reason ||= 'max_records' if @records >= @max_records
      @reason ||= 'max_bytes' if @bytes >= @max_bytes
      @reason ||= 'max_entities' if @entities >= @max_entities
    end
  end
end

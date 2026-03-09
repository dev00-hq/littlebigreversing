# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'tmpdir'

require_relative '../scripts/lib/analysis_pipeline'

class AnalysisPipelineTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('analysis-pipeline-test')
    build_fixture(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_stage_1_resume_continues_without_duplicates
    run_id = '20260212T220000Z'

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 1,
      resume: false,
      input_scope: 'index_normalized',
      max_records: 3,
      max_bytes: 50_000,
      max_entities: 1_000,
      chunk_size: 2
    ).execute

    partial_records = read_jsonl(stage1_path(run_id))
    assert_equal 3, partial_records.length

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 1,
      resume: true,
      input_scope: 'index_normalized',
      max_records: 100,
      max_bytes: 200_000,
      max_entities: 1_000,
      chunk_size: 2
    ).execute

    records = read_jsonl(stage1_path(run_id))
    assert_equal 14, records.length

    ids = records.map { |row| row['record_id'] }
    assert_equal ids.uniq.length, ids.length

    manifest = read_manifest(run_id)
    assert_equal 'completed', manifest.dig('stages', '1', 'status')
    assert_nil manifest.dig('stages', '1', 'metrics', 'limit_hit')
  end

  def test_stage_2_resume_clears_limit_hit_and_avoids_duplicates
    run_id = '20260212T220050Z'

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 2,
      resume: false,
      input_scope: 'index_normalized',
      max_records: 5,
      max_bytes: 50_000,
      max_entities: 1_000,
      chunk_size: 2
    ).execute

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 2,
      resume: true,
      input_scope: 'index_normalized',
      max_records: 100,
      max_bytes: 200_000,
      max_entities: 5_000,
      chunk_size: 2
    ).execute

    claims = read_jsonl(claims_path)
    claim_ids = claims.map { |row| row['claim_id'] }
    assert_equal claim_ids.uniq.length, claim_ids.length

    manifest = read_manifest(run_id)
    assert_equal 'completed', manifest.dig('stages', '2', 'status')
    assert_nil manifest.dig('stages', '2', 'metrics', 'limit_hit')
  end

  def test_pipeline_stops_after_partial_stage
    run_id = '20260212T220075Z'

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 5,
      resume: false,
      input_scope: 'index_normalized',
      max_records: 1,
      max_bytes: 50_000,
      max_entities: 1_000,
      chunk_size: 1
    ).execute

    manifest = read_manifest(run_id)
    assert_equal 'completed', manifest.dig('stages', '0', 'status')
    assert_equal 'partial', manifest.dig('stages', '1', 'status')
    refute manifest.fetch('stages', {}).key?('2')
    refute File.exist?(claims_path)
  end

  def test_stage_4_respects_limits_and_resume_without_raw_duplicates
    run_id = '20260212T220090Z'

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 4,
      resume: false,
      input_scope: 'with_raw',
      max_records: 20,
      max_bytes: 1_000_000,
      max_entities: 2_000,
      chunk_size: 4
    ).execute

    partial_manifest = read_manifest(run_id)
    assert_equal 'partial', partial_manifest.dig('stages', '4', 'status')
    assert_equal 'max_records', partial_manifest.dig('stages', '4', 'metrics', 'limit_hit')
    assert_operator read_jsonl(stage4_raw_delta_path).length, :<=, 20

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 4,
      resume: true,
      input_scope: 'with_raw',
      max_records: 200,
      max_bytes: 5_000_000,
      max_entities: 20_000,
      chunk_size: 4
    ).execute

    records = read_jsonl(stage4_raw_delta_path)
    ids = records.map { |row| row['record_id'] }
    assert_equal 30, records.length
    assert_equal ids.uniq.length, ids.length

    manifest = read_manifest(run_id)
    assert_equal 'completed', manifest.dig('stages', '4', 'status')
    assert_nil manifest.dig('stages', '4', 'metrics', 'limit_hit')
  end

  def test_stage_2_is_deterministic
    run_a = '20260212T220100Z'
    run_b = '20260212T220200Z'

    pipeline_options = {
      root_dir: @tmpdir,
      stage_target: 2,
      resume: false,
      input_scope: 'index_normalized',
      max_records: 500,
      max_bytes: 1_000_000,
      max_entities: 5_000,
      chunk_size: 3
    }

    AnalysisPipeline.new(**pipeline_options.merge(run_id: run_a)).execute
    claims_a = File.read(claims_path)
    entities_a = File.read(entities_path)

    AnalysisPipeline.new(**pipeline_options.merge(run_id: run_b)).execute
    claims_b = File.read(claims_path)
    entities_b = File.read(entities_path)

    assert_equal claims_a, claims_b
    assert_equal entities_a, entities_b
  end

  def test_stage_5_writes_quality_and_indexes
    run_id = '20260212T220300Z'

    AnalysisPipeline.new(
      root_dir: @tmpdir,
      run_id: run_id,
      stage_target: 5,
      resume: false,
      input_scope: 'index_normalized',
      max_records: 500,
      max_bytes: 1_000_000,
      max_entities: 5_000,
      chunk_size: 3
    ).execute

    assert File.file?(File.join(@tmpdir, 'runs', run_id, 'quality_report.json'))
    assert File.file?(File.join(@tmpdir, 'corpus', 'analysis', 'index', 'by_topic_id.json'))
    assert File.file?(File.join(@tmpdir, 'corpus', 'analysis', 'index', 'by_kind.json'))
    assert File.file?(File.join(@tmpdir, 'corpus', 'analysis', 'index', 'by_entity.json'))

    report = JSON.parse(File.read(File.join(@tmpdir, 'runs', run_id, 'quality_report.json')))
    assert_operator report.dig('coverage', 'claims').to_i, :>, 0
    assert_operator report.dig('provenance_completeness', 'ratio').to_f, :>=, 0.9
  end

  private

  def stage1_path(_run_id)
    File.join(@tmpdir, 'corpus', 'analysis', 'stage1_records.jsonl')
  end

  def claims_path
    File.join(@tmpdir, 'corpus', 'analysis', 'stage2_claims.jsonl')
  end

  def entities_path
    File.join(@tmpdir, 'corpus', 'analysis', 'stage2_entities.jsonl')
  end

  def stage4_raw_delta_path
    File.join(@tmpdir, 'corpus', 'analysis', 'stage4_raw_delta.jsonl')
  end

  def read_manifest(run_id)
    JSON.parse(File.read(File.join(@tmpdir, 'runs', run_id, 'analysis_manifest.json')))
  end

  def read_jsonl(path)
    return [] unless File.file?(path)

    File.readlines(path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
  end

  def write_jsonl(path, rows)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'w') do |file|
      rows.each { |row| file.puts(JSON.generate(row)) }
    end
  end

  def write_text(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def build_fixture(root)
    write_jsonl(
      File.join(root, 'corpus', 'index', 'topics_discovered.jsonl'),
      [
        {
          'topic_id' => 100,
          'title' => 'HQR format and toolchain',
          'excerpt' => 'workflow for import/export',
          'topic_url' => 'https://example.test/t/100'
        }
      ]
    )

    write_jsonl(
      File.join(root, 'corpus', 'index', 'topic_classification.jsonl'),
      [
        {
          'topic_id' => 100,
          'title' => 'HQR format and toolchain',
          'first_post_preview' => 'tool editor issue and crash',
          'topic_url' => 'https://example.test/t/100'
        }
      ]
    )

    write_jsonl(
      File.join(root, 'corpus', 'index', 'evidence_index.jsonl'),
      [
        {
          'topic_id' => 100,
          'post_id' => 1001,
          'source_url' => 'https://example.test/t/100/1',
          'excerpt' => 'offset and checksum warning',
          'matched_terms' => %w[offset checksum warning]
        }
      ]
    )

    write_jsonl(
      File.join(root, 'corpus', 'normalized', 'topics_lba2.jsonl'),
      [
        {
          'topic_id' => 100,
          'title' => 'HQR format and toolchain',
          'slug' => 'hqr-format-toolchain',
          'topic_url' => 'https://example.test/t/100'
        }
      ]
    )

    write_jsonl(
      File.join(root, 'corpus', 'normalized', 'posts_lba2.jsonl'),
      [
        {
          'topic_id' => 100,
          'post_id' => 1001,
          'raw' => 'Use the editor tool to replace entries in HQR and import assets.',
          'cooked' => '',
          'post_url' => 'https://example.test/t/100/1'
        },
        {
          'topic_id' => 100,
          'post_id' => 1002,
          'raw' => 'Potential crash issue when offsets are wrong. Sendell glossary mention.',
          'cooked' => '',
          'post_url' => 'https://example.test/t/100/2'
        }
      ]
    )

    write_jsonl(
      File.join(root, 'corpus', 'raw', 'posts', '100.jsonl'),
      (1..30).map do |n|
        {
          'topic_id' => 100,
          'id' => 2000 + n,
          'raw' => "Raw post #{n}: use editor tool to replace HQR entries and avoid crash issue.",
          'cooked' => '',
          'post_url' => "https://example.test/t/100/#{n}"
        }
      end
    )

    write_text(File.join(root, 'spec', 'formats.md'), "# Formats\n\nHQR entry offsets\n")
    write_text(File.join(root, 'spec', 'tools.md'), "# Tools\n\nEditor utility workflow\n")
    write_text(File.join(root, 'spec', 'workflows.md'), "# Workflows\n\nImport then export\n")
    write_text(File.join(root, 'spec', 'glossary.md'), "# Glossary\n\nSendell\n")
  end
end

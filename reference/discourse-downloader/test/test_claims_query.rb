# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class ClaimsQueryCliTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('claims-query-test')
    @analysis_dir = File.join(@tmpdir, 'corpus', 'analysis')
    FileUtils.mkdir_p(@analysis_dir)
    write_fixtures
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_prefers_merged_claims_by_default
    stdout, _stderr, status = run_cli('--format', 'jsonl')

    assert_equal 0, status
    ids = parse_jsonl_stdout(stdout).map { |row| row['claim_id'] }
    assert_equal %w[c-3 c-2 c-1], ids
    refute_includes ids, 'b-1'
  end

  def test_falls_back_to_base_claims_when_merged_missing
    FileUtils.rm_f(File.join(@analysis_dir, 'stage2_claims_merged.jsonl'))

    stdout, _stderr, status = run_cli('--format', 'jsonl')

    assert_equal 0, status
    ids = parse_jsonl_stdout(stdout).map { |row| row['claim_id'] }
    assert_equal ['b-1'], ids
  end

  def test_filters_claim_kind
    stdout, _stderr, status = run_cli('--claim-kind', 'PitFall')

    assert_equal 0, status
    ids = parse_jsonl_stdout(stdout).map { |row| row['claim_id'] }
    assert_equal ['c-3'], ids
  end

  def test_filters_topic_id
    stdout, _stderr, status = run_cli('--topic-id', '2')

    assert_equal 0, status
    ids = parse_jsonl_stdout(stdout).map { |row| row['claim_id'] }
    assert_equal ['c-1'], ids
  end

  def test_filters_min_confidence
    stdout, _stderr, status = run_cli('--min-confidence', '0.85')

    assert_equal 0, status
    ids = parse_jsonl_stdout(stdout).map { |row| row['claim_id'] }
    assert_equal ['c-1'], ids
  end

  def test_filters_entity_keyword
    stdout, _stderr, status = run_cli('--entity', 'OFF')

    assert_equal 0, status
    ids = parse_jsonl_stdout(stdout).map { |row| row['claim_id'] }
    assert_equal ['c-1'], ids
  end

  def test_combines_filters_with_and_semantics
    stdout, _stderr, status = run_cli(
      '--claim-kind', 'format',
      '--topic-id', '2',
      '--min-confidence', '0.8',
      '--entity', 'hq'
    )

    assert_equal 0, status
    rows = parse_jsonl_stdout(stdout)
    assert_equal 1, rows.length
    assert_equal 'c-1', rows.first['claim_id']
  end

  def test_limit_applies_after_stable_sort
    stdout, _stderr, status = run_cli('--limit', '2')

    assert_equal 0, status
    ids = parse_jsonl_stdout(stdout).map { |row| row['claim_id'] }
    assert_equal %w[c-3 c-2], ids
  end

  def test_markdown_is_grouped_by_topic_and_has_provenance
    stdout, _stderr, status = run_cli('--format', 'md')

    assert_equal 0, status
    assert_includes stdout, '## Topic 1: Topic One'
    assert_includes stdout, '## Topic 2: Topic Two'
    assert_includes stdout, 'provenance: `corpus/index/evidence_index.jsonl:11`'
  end

  def test_default_stdout_behavior_without_output_files
    stdout, _stderr, status = run_cli

    assert_equal 0, status
    refute_equal '', stdout
  end

  def test_writes_both_output_files_when_requested
    out_jsonl = File.join(@tmpdir, 'exports', 'claims.jsonl')
    out_md = File.join(@tmpdir, 'exports', 'claims.md')
    stdout, _stderr, status = run_cli('--format', 'both', '--out-jsonl', out_jsonl, '--out-md', out_md)

    assert_equal 0, status
    assert_equal '', stdout
    assert File.file?(out_jsonl)
    assert File.file?(out_md)
  end

  def test_min_confidence_out_of_range_returns_exit_2
    _stdout, stderr, status = run_cli('--min-confidence', '1.5')

    assert_equal 2, status
    assert_includes stderr, 'min-confidence must be in range 0.0..1.0'
  end

  def test_non_integer_topic_id_returns_exit_2
    _stdout, stderr, status = run_cli('--topic-id', 'abc')

    assert_equal 2, status
    assert_includes stderr, 'invalid argument'
  end

  private

  def run_cli(*args)
    script = File.expand_path('../scripts/query_claims.rb', __dir__)
    command = [RbConfig.ruby, script, '--root-dir', @tmpdir, *args]
    stdout, stderr, status = Open3.capture3(*command)
    [stdout, stderr, status.exitstatus]
  end

  def parse_jsonl_stdout(stdout)
    stdout.lines.filter_map do |line|
      stripped = line.strip
      next if stripped.empty?

      JSON.parse(stripped)
    end
  end

  def write_fixtures
    write_jsonl(
      File.join(@analysis_dir, 'stage2_claims_merged.jsonl'),
      [
        {
          'claim_id' => 'c-1',
          'claim_kind' => 'format',
          'claim_text' => 'format references: hqr, offset',
          'entities' => %w[hqr offset],
          'confidence' => 0.90,
          'topic_id' => 2,
          'provenance' => {
            'source_file' => 'corpus/index/evidence_index.jsonl',
            'line_no' => 11
          }
        },
        {
          'claim_id' => 'c-2',
          'claim_kind' => 'tool',
          'claim_text' => 'tool references: editor',
          'entities' => ['editor'],
          'confidence' => 0.50,
          'topic_id' => 1,
          'provenance' => {
            'source_file' => 'corpus/normalized/posts_lba2.jsonl',
            'line_no' => 21
          }
        },
        {
          'claim_id' => 'c-3',
          'claim_kind' => 'pitfall',
          'claim_text' => 'pitfall references: crash',
          'entities' => ['crash'],
          'confidence' => 0.80,
          'topic_id' => 1,
          'provenance' => {
            'source_file' => 'corpus/normalized/posts_lba2.jsonl',
            'line_no' => 33
          }
        }
      ]
    )

    write_jsonl(
      File.join(@analysis_dir, 'stage2_claims.jsonl'),
      [
        {
          'claim_id' => 'b-1',
          'claim_kind' => 'workflow',
          'claim_text' => 'workflow references: import',
          'entities' => ['import'],
          'confidence' => 0.71,
          'topic_id' => 9,
          'provenance' => {
            'source_file' => 'corpus/index/evidence_index.jsonl',
            'line_no' => 101
          }
        }
      ]
    )

    write_jsonl(
      File.join(@analysis_dir, 'topic_cards_merged.jsonl'),
      [
        {
          'topic_id' => 1,
          'title' => 'Topic One'
        },
        {
          'topic_id' => 2,
          'title' => 'Topic Two'
        }
      ]
    )
  end

  def write_jsonl(path, rows)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'w') do |file|
      rows.each { |row| file.puts(JSON.generate(row)) }
    end
  end
end

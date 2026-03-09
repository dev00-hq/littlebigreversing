#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'time'

require_relative 'lib/analysis_pipeline'

DEFAULTS = {
  stage: 5,
  resume: false,
  run_id: nil,
  root_dir: '.',
  input_scope: AnalysisPipeline::DEFAULT_INPUT_SCOPE,
  max_records: AnalysisPipeline::DEFAULT_MAX_RECORDS,
  max_bytes: AnalysisPipeline::DEFAULT_MAX_BYTES,
  max_entities: AnalysisPipeline::DEFAULT_MAX_ENTITIES,
  chunk_size: AnalysisPipeline::DEFAULT_CHUNK_SIZE
}.freeze

def parse_args(argv)
  options = DEFAULTS.dup

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby scripts/analyze_corpus.rb [options]'

    opts.on('--stage N', Integer, 'Highest stage to execute (0-5, default: 5)') { |v| options[:stage] = v }
    opts.on('--resume', 'Resume from the latest analysis run or --run-id') { options[:resume] = true }
    opts.on('--run-id ID', 'Run ID to use (default: current UTC timestamp)') { |v| options[:run_id] = v }
    opts.on('--root-dir DIR', 'Project root directory (default: .)') { |v| options[:root_dir] = v }
    opts.on('--input-scope SCOPE', 'Input scope: index_normalized|with_raw') { |v| options[:input_scope] = v }
    opts.on('--max-records N', Integer, 'Hard limit for records processed per stage') { |v| options[:max_records] = v }
    opts.on('--max-bytes N', Integer, 'Hard limit for bytes parsed per stage') { |v| options[:max_bytes] = v }
    opts.on('--max-entities N', Integer, 'Hard limit for claims/entities emitted per stage') { |v| options[:max_entities] = v }
    opts.on('--chunk-size N', Integer, 'Chunk size before checkpoint/flush (default: 250)') { |v| options[:chunk_size] = v }
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end

  parser.parse!(argv)
  options
end

def latest_analysis_run_id(root_dir)
  runs_root = File.join(File.expand_path(root_dir), 'runs')
  return nil unless Dir.exist?(runs_root)

  candidates = Dir.glob(File.join(runs_root, '*')).select do |path|
    File.directory?(path) && File.file?(File.join(path, 'analysis_manifest.json'))
  end

  return nil if candidates.empty?

  File.basename(candidates.sort.last)
end

def resolve_run_id(options)
  return options[:run_id] if options[:run_id]

  if options[:resume]
    resume_id = latest_analysis_run_id(options[:root_dir])
    return resume_id if resume_id
  end

  Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
end

opts = parse_args(ARGV)
run_id = resolve_run_id(opts)

pipeline = AnalysisPipeline.new(
  root_dir: opts[:root_dir],
  run_id: run_id,
  stage_target: opts[:stage],
  resume: opts[:resume],
  input_scope: opts[:input_scope],
  max_records: opts[:max_records],
  max_bytes: opts[:max_bytes],
  max_entities: opts[:max_entities],
  chunk_size: opts[:chunk_size]
)

manifest = pipeline.execute

puts "Analysis run complete: #{manifest['run_id']}"
puts "Manifest: #{File.join(File.expand_path(opts[:root_dir]), 'runs', manifest['run_id'], 'analysis_manifest.json')}"
puts "Stage 1 output: #{File.join(File.expand_path(opts[:root_dir]), 'corpus', 'analysis', 'stage1_records.jsonl')}"
puts "Stage 2 claims: #{File.join(File.expand_path(opts[:root_dir]), 'corpus', 'analysis', 'stage2_claims.jsonl')}"
puts "Stage 3 cards: #{File.join(File.expand_path(opts[:root_dir]), 'corpus', 'analysis', 'topic_cards.jsonl')}"

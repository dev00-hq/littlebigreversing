#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'optparse'

require_relative 'lib/claims_query'

FORMATS = %w[jsonl md both].freeze

def parse_args(argv)
  options = {
    root_dir: '.',
    claims_path: nil,
    claim_kind: nil,
    topic_id: nil,
    min_confidence: nil,
    entity_keyword: nil,
    format: 'jsonl',
    out_jsonl: nil,
    out_md: nil,
    limit: nil
  }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby scripts/query_claims.rb [options]'

    opts.on('--root-dir DIR', 'Project root directory (default: .)') { |v| options[:root_dir] = v }
    opts.on('--claims-path FILE', 'Explicit claims JSONL path') { |v| options[:claims_path] = v }
    opts.on('--claim-kind KIND', 'Filter by claim_kind (case-insensitive exact)') { |v| options[:claim_kind] = v }
    opts.on('--topic-id ID', Integer, 'Filter by topic_id') { |v| options[:topic_id] = v }
    opts.on('--min-confidence FLOAT', Float, 'Filter by minimum confidence (0.0..1.0)') do |v|
      options[:min_confidence] = v
    end
    opts.on('--entity KEYWORD', 'Filter by entity keyword (case-insensitive substring)') do |v|
      options[:entity_keyword] = v
    end
    opts.on('--format FORMAT', "Output format: #{FORMATS.join('|')} (default: jsonl)") { |v| options[:format] = v }
    opts.on('--out-jsonl FILE', 'Write JSONL output to file') { |v| options[:out_jsonl] = v }
    opts.on('--out-md FILE', 'Write Markdown output to file') { |v| options[:out_md] = v }
    opts.on('--limit N', Integer, 'Maximum matched claims to output after sorting') { |v| options[:limit] = v }
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit 0
    end
  end

  parser.parse!(argv)

  unless FORMATS.include?(options[:format])
    raise OptionParser::InvalidArgument, "format must be one of: #{FORMATS.join(', ')}"
  end

  if options[:min_confidence] && !(0.0..1.0).cover?(options[:min_confidence])
    raise OptionParser::InvalidArgument, 'min-confidence must be in range 0.0..1.0'
  end

  if options[:limit] && options[:limit] < 1
    raise OptionParser::InvalidArgument, 'limit must be >= 1'
  end

  options
end

def write_output_file(path, content)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

def main(argv)
  options = parse_args(argv)
  claims_path = ClaimsQuery.resolve_claims_path(root_dir: options[:root_dir], claims_path: options[:claims_path])
  claims = ClaimsQuery.query_claims(
    path: claims_path,
    filters: {
      claim_kind: options[:claim_kind],
      topic_id: options[:topic_id],
      min_confidence: options[:min_confidence],
      entity_keyword: options[:entity_keyword]
    },
    limit: options[:limit]
  )

  cards_path = ClaimsQuery.resolve_topic_cards_path(claims_path)
  topic_titles = ClaimsQuery.load_topic_titles(cards_path)

  jsonl_text = ClaimsQuery.render_jsonl(claims)
  markdown_text = ClaimsQuery.render_markdown(claims, topic_titles: topic_titles)

  stdout_segments = []

  if %w[jsonl both].include?(options[:format])
    if options[:out_jsonl]
      write_output_file(options[:out_jsonl], jsonl_text)
    else
      stdout_segments << jsonl_text
    end
  end

  if %w[md both].include?(options[:format])
    if options[:out_md]
      write_output_file(options[:out_md], markdown_text)
    else
      stdout_segments << markdown_text
    end
  end

  unless stdout_segments.empty?
    output = options[:format] == 'both' ? stdout_segments.join("\n---\n") : stdout_segments.first
    $stdout.write(output)
  end
end

begin
  main(ARGV)
rescue OptionParser::ParseError => e
  warn e.message
  exit 2
rescue ClaimsQuery::Error => e
  warn e.message
  exit e.exit_code
rescue StandardError => e
  warn e.message
  exit 1
end

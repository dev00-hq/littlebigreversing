#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'

require_relative 'lib/evidence_builder'
require_relative 'lib/output_helpers'

options = {
  posts_path: './corpus/posts_lba2.jsonl',
  out_path: './corpus/index/evidence_index.jsonl',
  base_url: 'https://forum.magicball.net'
}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/build_evidence_index.rb [options]'

  opts.on('--posts FILE', 'Input posts JSONL path') { |v| options[:posts_path] = v }
  opts.on('--out FILE', 'Output evidence JSONL path') { |v| options[:out_path] = v }
  opts.on('--base-url URL', 'Base forum URL') { |v| options[:base_url] = v }
  opts.on('-h', '--help', 'Show help') do
    puts opts
    exit
  end
end.parse!

posts = File.readlines(options[:posts_path], chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
evidence = EvidenceBuilder.build(posts, base_topic_url: options[:base_url])
  .sort_by { |row| [row['kind'], row['topic_id'].to_i, row['post_number'].to_i] }

OutputHelpers.write_jsonl(options[:out_path], evidence)
puts "Wrote #{evidence.length} evidence rows to #{options[:out_path]}"

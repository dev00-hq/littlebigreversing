#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'optparse'
require 'ostruct'
require 'set'
require 'time'
require 'uri'

require_relative 'lib/classifier'
require_relative 'lib/config_loader'
require_relative 'lib/discourse_client'
require_relative 'lib/evidence_builder'
require_relative 'lib/output_helpers'
require_relative 'lib/post_extractors'

DEFAULT_CATEGORY_URLS = [
  'https://forum.magicball.net/c/lba-modifications/10',
  'https://forum.magicball.net/c/lba-projects/8'
].freeze

DEFAULT_CONFIG_FILE = './mbn'
DEFAULT_MIXED_POLICY = 'flagged'


def parse_args(argv)
  options = OpenStruct.new
  options.categories = DEFAULT_CATEGORY_URLS.dup
  options.out_dir = '.'
  options.config_file = DEFAULT_CONFIG_FILE
  options.rules_file = nil
  options.username = nil
  options.password = nil
  options.password_env = nil
  options.api_key = nil
  options.api_user = nil
  options.verbose = false
  options.recurse_subcategories = true
  options.mixed_policy = DEFAULT_MIXED_POLICY
  options.min_delay_ms = DiscourseClient::DEFAULT_MIN_DELAY_MS
  options.max_delay_ms = DiscourseClient::DEFAULT_MAX_DELAY_MS
  options.max_retries = DiscourseClient::DEFAULT_REQUEST_RETRIES
  options.backoff_base_ms = DiscourseClient::DEFAULT_BACKOFF_BASE_MS

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby scripts/build_corpus.rb [options]'

    opts.on('-c', '--config FILE', "Credentials/config file (default: #{DEFAULT_CONFIG_FILE})") do |file|
      options.config_file = file
    end

    opts.on('--categories URLS', 'Comma-separated category URLs') do |urls|
      options.categories = urls.split(',').map(&:strip).reject(&:empty?)
    end

    opts.on('--out-dir DIR', 'Output root directory (default: current dir)') do |dir|
      options.out_dir = dir
    end

    opts.on('--rules FILE', 'Optional YAML rules override for classifier') do |file|
      options.rules_file = file
    end

    opts.on('-u', '--username USERNAME', 'Discourse username/email') do |value|
      options.username = value
    end

    opts.on('-p', '--password PASSWORD', 'Discourse password') do |value|
      options.password = value
    end

    opts.on('--password-env ENV_VAR', 'Read password from ENV_VAR') do |env_var|
      options.password_env = env_var
    end

    opts.on('--api-key KEY', 'Discourse API key') do |value|
      options.api_key = value
    end

    opts.on('--api-user USER', 'Discourse API username') do |value|
      options.api_user = value
    end

    opts.on('--[no-]recurse-subcategories', 'Recursively crawl child categories (default: enabled)') do |value|
      options.recurse_subcategories = value
    end

    opts.on('--mixed-policy POLICY', 'How mixed topics are handled: exclude|include|flagged') do |value|
      allowed = %w[exclude include flagged]
      raise OptionParser::InvalidArgument, value unless allowed.include?(value)

      options.mixed_policy = value
    end

    opts.on('--min-delay-ms N', Integer, 'Minimum delay between requests in milliseconds') do |value|
      options.min_delay_ms = value
    end

    opts.on('--max-delay-ms N', Integer, 'Maximum delay between requests in milliseconds') do |value|
      options.max_delay_ms = value
    end

    opts.on('--max-retries N', Integer, 'Maximum retries for transient failures') do |value|
      options.max_retries = value
    end

    opts.on('--backoff-base-ms N', Integer, 'Exponential backoff base in milliseconds') do |value|
      options.backoff_base_ms = value
    end

    opts.on('-v', '--verbose', 'Verbose output') do
      options.verbose = true
    end

    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end.parse!(argv)

  options
end

def log(verbose, message)
  puts(message) if verbose
end

def parse_category_url(url)
  uri = URI.parse(url)
  raise "Invalid category URL: #{url}" unless uri.is_a?(URI::HTTP) && uri.host

  path = uri.path.to_s.chomp('/')
  with_slug = path.match(%r{\A/c/(.+?)/([0-9]+)(?:/.*)?\z})
  bare_id = path.match(%r{\A/c/([0-9]+)(?:/.*)?\z})
  raise "URL is not a category path: #{url}" unless with_slug || bare_id

  category_id = (with_slug ? with_slug[2] : bare_id[1]).to_i
  category_path = with_slug ? "/c/#{with_slug[1]}/#{category_id}" : "/c/#{category_id}"

  {
    url: url,
    base_url: "#{uri.scheme}://#{uri.host}",
    path: category_path,
    category_id: category_id,
    source_category_id: category_id
  }
end

def category_json_path(path)
  return nil unless path

  return path if path.include?('.json')

  if path.include?('?')
    base, query = path.split('?', 2)
    "#{base}.json?#{query}"
  else
    "#{path}.json"
  end
end

def category_path_for_id(category_id)
  "/c/#{category_id}"
end

def resolve_category_targets(client, categories, recurse_subcategories, verbose)
  deduped = categories
    .sort_by { |category| [category[:base_url], category[:category_id].to_i, category[:path]] }
    .uniq { |category| [category[:base_url], category[:category_id].to_i] }

  return deduped unless recurse_subcategories

  site_categories = Array(client.get_json('/site.json')['categories'])
  by_id = {}
  children_by_parent = Hash.new { |memo, key| memo[key] = [] }

  site_categories.each do |entry|
    category_id = entry['id'].to_i
    by_id[category_id] = entry
    parent_id = entry['parent_category_id']
    children_by_parent[parent_id.to_i] << category_id if parent_id
  end

  resolved = []

  deduped.each do |root|
    queue = [root[:category_id].to_i]
    seen = Set.new

    until queue.empty?
      current_id = queue.shift
      next if seen.include?(current_id)

      seen << current_id
      entry = by_id[current_id] || {}
      resolved << {
        url: "#{root[:base_url]}#{category_path_for_id(current_id)}",
        base_url: root[:base_url],
        path: category_path_for_id(current_id),
        category_id: current_id,
        source_category_id: root[:category_id],
        slug: entry['slug']
      }

      queue.concat(children_by_parent[current_id].sort)
    end
  end

  normalized = resolved
    .sort_by { |category| [category[:base_url], category[:category_id].to_i, category[:source_category_id].to_i] }
    .uniq { |category| [category[:base_url], category[:category_id].to_i] }

  log(
    verbose,
    "Resolved #{normalized.length} category target(s) from #{deduped.length} seed category URL(s)"
  )

  normalized
rescue StandardError => e
  log(verbose, "Warning: failed to recurse subcategories: #{e.message}")
  deduped
end

def load_credentials(options)
  config = ConfigLoader.load_config(options.config_file)

  username = options.username || config[:username]
  password = options.password || config[:password]
  password = ENV.fetch(options.password_env) if options.password_env

  {
    username: username,
    password: password,
    api_key: options.api_key || config[:api_key],
    api_user: options.api_user || config[:api_user]
  }
end

def absolute_url(base_url, maybe_relative)
  return nil if maybe_relative.nil? || maybe_relative.empty?

  uri = URI.parse(maybe_relative)
  return maybe_relative if uri.is_a?(URI::HTTP)

  URI.join(base_url, maybe_relative).to_s
rescue URI::InvalidURIError
  maybe_relative
end

def stage_a_discover_topics(client, categories, verbose)
  discovered = []

  categories.each do |category|
    json_path = category_json_path(category[:path])
    seen_pages = Set.new
    category_count = 0

    while json_path && !seen_pages.include?(json_path)
      seen_pages << json_path

      data = client.get_json(json_path)
      topics = data.dig('topic_list', 'topics') || []
      category_count += topics.length

      topics.each do |topic|
        discovered << {
          'topic_id' => topic['id'],
          'title' => topic['title'],
          'slug' => topic['slug'],
          'posts_count' => topic['posts_count'],
          'views' => topic['views'],
          'created_at' => topic['created_at'],
          'last_posted_at' => topic['last_posted_at'],
          'tags' => topic['tags'] || [],
          'excerpt' => topic['excerpt'],
          'category_id' => topic['category_id'],
          'category_id_source' => category[:category_id],
          'category_path' => category[:path],
          'category_url' => category[:url],
          'topic_url' => "#{category[:base_url]}/t/#{topic['id']}/1"
        }
      end

      json_path = category_json_path(data.dig('topic_list', 'more_topics_url'))
    end

    log(verbose, "Discovered #{category_count} topics in #{category[:path]} across #{seen_pages.length} page(s)")
  end

  by_topic = {}
  discovered.sort_by { |row| [row['topic_id'].to_i, row['category_path']] }.each do |row|
    by_topic[row['topic_id']] ||= row
  end

  by_topic.values.sort_by { |row| row['topic_id'].to_i }
end

def collect_topic_stream_ids(client, topic_json, topic_id, verbose)
  stream_ids = Array(topic_json.dig('post_stream', 'stream')).compact
  if stream_ids.empty?
    stream_ids = Array(topic_json.dig('post_stream', 'posts')).map { |post| post['id'] }.compact
  end

  expected_count = topic_json['posts_count'].to_i
  return stream_ids.uniq if expected_count <= 0 || stream_ids.length >= expected_count

  seen_ids = stream_ids.each_with_object({}) { |post_id, memo| memo[post_id] = true }
  last_post_number = Array(topic_json.dig('post_stream', 'posts')).map { |post| post['post_number'].to_i }.max || 1
  stagnant_rounds = 0

  while stream_ids.length < expected_count
    page_json = client.get_json("/t/#{topic_id}/#{last_post_number + 1}.json")
    page_posts = Array(page_json.dig('post_stream', 'posts'))
    break if page_posts.empty?

    added = 0
    page_posts.each do |post|
      post_id = post['id']
      next if post_id.nil? || seen_ids[post_id]

      seen_ids[post_id] = true
      stream_ids << post_id
      added += 1
    end

    newest_post_number = page_posts.map { |post| post['post_number'].to_i }.max
    break if newest_post_number.nil? || newest_post_number <= last_post_number

    last_post_number = newest_post_number

    if added.zero?
      stagnant_rounds += 1
      break if stagnant_rounds >= 2
    else
      stagnant_rounds = 0
    end
  end

  if stream_ids.length < expected_count
    log(verbose, "Warning: topic #{topic_id} has #{expected_count} expected posts but only #{stream_ids.length} IDs discovered")
  end

  stream_ids.uniq
rescue StandardError => e
  log(verbose, "Warning: failed to paginate topic stream for topic #{topic_id}: #{e.message}")
  stream_ids.uniq
end

def stage_b_classify_topics(client, topics, classifier, verbose)
  results = []
  total = topics.length

  topics.each_with_index do |topic, index|
    topic_id = topic['topic_id']
    first_post_raw = ''

    begin
      first_post_raw = client.get("/raw/#{topic_id}/1")
    rescue StandardError => e
      log(verbose, "Warning: failed to fetch first post raw for topic #{topic_id}: #{e.message}")
    end

    classified = classifier.classify(title: topic['title'], first_post_raw: first_post_raw)

    results << {
      'topic_id' => topic_id,
      'title' => topic['title'],
      'label' => classified[:label],
      'score' => classified[:score],
      'matched_rules' => classified[:matched_rules],
      'first_post_preview' => first_post_raw.gsub(/\s+/, ' ')[0, 280],
      'topic_url' => topic['topic_url']
    }

    if verbose && (((index + 1) % 100).zero? || index == total - 1)
      log(verbose, "Classified #{index + 1}/#{total} topics")
    end
  end

  results.sort_by { |row| row['topic_id'].to_i }
end

def fetch_topic_posts(client, base_url, topic_id, classification_row, mark_mixed_review, verbose)
  topic_json = client.get_json("/t/#{topic_id}.json")
  stream_ids = collect_topic_stream_ids(client, topic_json, topic_id, verbose)

  posts = []
  raw_posts = []

  stream_ids.each do |post_id|
    begin
      post = client.get_json("/posts/#{post_id}.json")
    rescue StandardError => e
      log(verbose, "Warning: failed to fetch post #{post_id} in topic #{topic_id}: #{e.message}")
      next
    end

    raw_posts << post

    raw = post['raw'] || ''
    cooked = post['cooked'] || ''
    topic_post_url = "#{base_url}/t/#{topic_id}/#{post['post_number']}"
    needs_review = mark_mixed_review && classification_row['label'] == 'mixed'

    links = PostExtractors.extract_links(raw: raw, cooked: cooked).map do |link|
      {
        'url' => absolute_url(base_url, link[:url]),
        'anchor_text' => link[:anchor_text]
      }
    end

    code_blocks = PostExtractors.extract_code_blocks(raw: raw, cooked: cooked).map do |block|
      {
        'kind' => block[:kind],
        'source' => block[:source],
        'language' => block[:language],
        'code' => block[:code]
      }
    end

    attachments = PostExtractors.extract_attachments(post, cooked: cooked).map do |attachment|
      {
        'url' => absolute_url(base_url, attachment[:url]),
        'filename' => attachment[:filename],
        'mime_type' => attachment[:mime_type]
      }
    end

    posts << {
      'topic_id' => topic_id,
      'topic_title' => topic_json['title'],
      'post_id' => post['id'],
      'post_number' => post['post_number'],
      'author' => post['username'] || post['name'],
      'author_username' => post['username'],
      'author_name' => post['name'],
      'raw' => raw,
      'cooked' => cooked,
      'created_at' => post['created_at'],
      'updated_at' => post['updated_at'],
      'reply_to_post_number' => post['reply_to_post_number'],
      'links' => links,
      'code_blocks' => code_blocks,
      'attachments' => attachments,
      'classification_label' => classification_row['label'],
      'classification_score' => classification_row['score'],
      'needs_review' => needs_review,
      'post_url' => topic_post_url
    }
  end

  [topic_json, posts, raw_posts]
end

def included_labels_for_policy(mixed_policy)
  return %w[lba2] if mixed_policy == 'exclude'

  %w[lba2 mixed]
end

def stage_c_fetch_topics(client, base_url, topics, classifications, raw_topics_dir, raw_posts_dir, mixed_policy, verbose)
  class_by_topic = classifications.each_with_object({}) { |row, memo| memo[row['topic_id']] = row }
  included_labels = included_labels_for_policy(mixed_policy)
  included_topic_ids = classifications.select { |row| included_labels.include?(row['label']) }.map { |row| row['topic_id'] }
  mark_mixed_review = (mixed_policy == 'flagged')

  topics_out = []
  posts_out = []

  included_topic_ids.sort_by(&:to_i).each do |topic_id|
    classification_row = class_by_topic[topic_id]
    topic_row = topics.find { |candidate| candidate['topic_id'] == topic_id }
    next unless topic_row

    log(verbose, "Fetching full topic #{topic_id} (#{classification_row['label']})")
    topic_json, posts, raw_posts = fetch_topic_posts(
      client,
      base_url,
      topic_id,
      classification_row,
      mark_mixed_review,
      verbose
    )

    OutputHelpers.write_json(File.join(raw_topics_dir, "#{topic_id}.json"), topic_json)
    OutputHelpers.write_jsonl(
      File.join(raw_posts_dir, "#{topic_id}.jsonl"),
      raw_posts.sort_by { |post| post['post_number'].to_i }
    )

    topics_out << {
      'topic_id' => topic_id,
      'title' => topic_json['title'] || topic_row['title'],
      'slug' => topic_json['slug'] || topic_row['slug'],
      'category_id' => topic_row['category_id'],
      'category_path' => topic_row['category_path'],
      'posts_count' => posts.length,
      'views' => topic_row['views'],
      'tags' => topic_row['tags'],
      'created_at' => topic_row['created_at'],
      'last_posted_at' => topic_row['last_posted_at'],
      'topic_url' => topic_row['topic_url'],
      'classification_label' => classification_row['label'],
      'classification_score' => classification_row['score'],
      'needs_review' => mark_mixed_review && classification_row['label'] == 'mixed'
    }

    posts_out.concat(posts)
  end

  [
    topics_out.sort_by { |row| row['topic_id'].to_i },
    posts_out.sort_by { |row| [row['topic_id'].to_i, row['post_number'].to_i] }
  ]
end

def build_links_rows(posts)
  rows = []

  posts.each do |post|
    Array(post['links']).each do |link|
      rows << [
        link['url'],
        post['topic_id'],
        post['post_id'],
        link['anchor_text']
      ]
    end
  end

  rows.sort_by { |row| [row[1].to_i, row[2].to_i, row[0].to_s] }
end

def stage_e_write_spec_docs(spec_dir, evidence)
  grouped = evidence.group_by { |row| row['kind'] }

  write_spec_doc(
    File.join(spec_dir, 'formats.md'),
    'Formats',
    grouped.fetch('format', [])
  )

  tools_plus_scripts = grouped.fetch('tool', []) + grouped.fetch('script', [])
  write_spec_doc(
    File.join(spec_dir, 'tools.md'),
    'Tools',
    tools_plus_scripts
  )

  workflows_plus_pitfalls = grouped.fetch('workflow', []) + grouped.fetch('pitfall', [])
  write_spec_doc(
    File.join(spec_dir, 'workflows.md'),
    'Workflows',
    workflows_plus_pitfalls
  )

  write_spec_doc(
    File.join(spec_dir, 'glossary.md'),
    'Glossary Candidates',
    grouped.fetch('glossary_candidate', [])
  )
end

def format_notes(notes)
  return nil unless notes.is_a?(Hash) && !notes.empty?

  notes.keys.sort.map do |key|
    value = notes[key]
    rendered = value.is_a?(Array) ? value.join(', ') : value.to_s
    "#{key}=#{rendered}"
  end.join(' ; ')
end

def write_spec_doc(path, title, entries)
  lines = ["# #{title}", '']

  if entries.empty?
    lines << '_No entries extracted in this run._'
  else
    sorted = entries.sort_by { |entry| [-entry['confidence'].to_f, entry['topic_id'].to_i, entry['post_number'].to_i] }
    sorted.each_with_index do |entry, index|
      lines << "#{index + 1}. #{entry['matched_terms'].uniq.join(', ')}"
      lines << "   - Source: #{entry['source_url']}"
      lines << "   - Excerpt: #{entry['excerpt']}"
      notes_line = format_notes(entry['notes'])
      lines << "   - Notes: #{notes_line}" if notes_line
    end
  end

  lines << ''
  OutputHelpers.ensure_dir(File.dirname(path))
  File.write(path, lines.join("\n"))
end

def collect_manifest_outputs(paths)
  paths.each_with_object([]) do |path, memo|
    next unless File.file?(path)

    memo << {
      'path' => path,
      'sha256' => OutputHelpers.sha256_for(path),
      'bytes' => File.size(path)
    }
  end
end

def main
  options = parse_args(ARGV)

  categories = options.categories.map { |url| parse_category_url(url) }
  base_urls = categories.map { |cat| cat[:base_url] }.uniq
  raise 'All categories must be on the same host' if base_urls.length != 1

  credentials = load_credentials(options)

  client = DiscourseClient.new(
    base_url: base_urls.first,
    api_key: credentials[:api_key],
    api_user: credentials[:api_user],
    username: credentials[:username],
    password: credentials[:password],
    verbose: options.verbose,
    request_retries: options.max_retries,
    min_delay_ms: options.min_delay_ms,
    max_delay_ms: options.max_delay_ms,
    backoff_base_ms: options.backoff_base_ms
  )

  classifier = TopicClassifier.from_yaml(options.rules_file)
  resolved_categories = resolve_category_targets(client, categories, options.recurse_subcategories, options.verbose)

  run_timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  output_root = File.expand_path(options.out_dir)

  corpus_dir = File.join(output_root, 'corpus')
  raw_dir = File.join(corpus_dir, 'raw')
  raw_topics_dir = File.join(raw_dir, 'topics')
  raw_posts_dir = File.join(raw_dir, 'posts')
  normalized_dir = File.join(corpus_dir, 'normalized')
  index_dir = File.join(corpus_dir, 'index')
  spec_dir = File.join(output_root, 'spec')
  run_dir = File.join(output_root, 'runs', run_timestamp)

  [raw_topics_dir, raw_posts_dir, normalized_dir, index_dir, spec_dir, run_dir].each do |dir|
    OutputHelpers.ensure_dir(dir)
  end

  log(options.verbose, 'Stage A: Discovering topics')
  discovered_topics = stage_a_discover_topics(client, resolved_categories, options.verbose)
  discovered_path = File.join(index_dir, 'topics_discovered.jsonl')
  OutputHelpers.write_jsonl(discovered_path, discovered_topics)

  log(options.verbose, 'Stage B: Classifying topics')
  classifications = stage_b_classify_topics(client, discovered_topics, classifier, options.verbose)
  class_path = File.join(index_dir, 'topic_classification.jsonl')
  mixed_path = File.join(index_dir, 'mixed_review_queue.jsonl')
  OutputHelpers.write_jsonl(class_path, classifications)
  OutputHelpers.write_jsonl(mixed_path, classifications.select { |row| row['label'] == 'mixed' })

  log(options.verbose, 'Stage C: Fetching included topics and posts')
  topics_lba2, posts_lba2 = stage_c_fetch_topics(
    client,
    base_urls.first,
    discovered_topics,
    classifications,
    raw_topics_dir,
    raw_posts_dir,
    options.mixed_policy,
    options.verbose
  )

  topics_norm_path = File.join(normalized_dir, 'topics_lba2.jsonl')
  posts_norm_path = File.join(normalized_dir, 'posts_lba2.jsonl')
  OutputHelpers.write_jsonl(topics_norm_path, topics_lba2)
  OutputHelpers.write_jsonl(posts_norm_path, posts_lba2)

  final_topics_path = File.join(corpus_dir, 'topics_lba2.jsonl')
  final_posts_path = File.join(corpus_dir, 'posts_lba2.jsonl')
  FileUtils.cp(topics_norm_path, final_topics_path)
  FileUtils.cp(posts_norm_path, final_posts_path)

  links_rows = build_links_rows(posts_lba2)
  links_path = File.join(corpus_dir, 'links.csv')
  OutputHelpers.write_csv(links_path, %w[url topic_id post_id anchor_text], links_rows)

  log(options.verbose, 'Stage D: Building evidence index')
  evidence = EvidenceBuilder.build(posts_lba2, base_topic_url: base_urls.first)
    .sort_by { |row| [row['kind'], row['topic_id'].to_i, row['post_number'].to_i] }
  evidence_path = File.join(index_dir, 'evidence_index.jsonl')
  OutputHelpers.write_jsonl(evidence_path, evidence)

  log(options.verbose, 'Stage E: Writing spec markdown documents')
  stage_e_write_spec_docs(spec_dir, evidence)

  manifest = {
    'run_timestamp_utc' => run_timestamp,
    'input_category_urls' => categories.map { |row| row[:url] },
    'resolved_category_urls' => resolved_categories.map { |row| row[:url] },
    'base_url' => base_urls.first,
    'credential_mode' => if credentials[:api_key] && credentials[:api_user]
                           'api_key'
                         elsif credentials[:username] && credentials[:password]
                           'username_password'
                         else
                           'anonymous'
                         end,
    'git_commit' => (`git rev-parse --short HEAD`.strip rescue nil),
    'classifier_rules' => {
      'rules_file' => options.rules_file,
      'default_rules' => options.rules_file.nil?
    },
    'mixed_policy' => options.mixed_policy,
    'rate_limit' => {
      'min_delay_ms' => options.min_delay_ms,
      'max_delay_ms' => options.max_delay_ms,
      'max_retries' => options.max_retries,
      'backoff_base_ms' => options.backoff_base_ms
    },
    'counts' => {
      'topics_discovered' => discovered_topics.length,
      'topics_lba2' => classifications.count { |row| row['label'] == 'lba2' },
      'topics_mixed' => classifications.count { |row| row['label'] == 'mixed' },
      'topics_undetermined' => classifications.count { |row| row['label'] == 'undetermined' },
      'topics_fetched' => topics_lba2.length,
      'posts_fetched' => posts_lba2.length,
      'links_extracted' => links_rows.length,
      'evidence_items' => evidence.length
    },
    'output_files' => collect_manifest_outputs(
      [
        discovered_path,
        class_path,
        mixed_path,
        topics_norm_path,
        posts_norm_path,
        final_topics_path,
        final_posts_path,
        links_path,
        evidence_path,
        File.join(spec_dir, 'formats.md'),
        File.join(spec_dir, 'tools.md'),
        File.join(spec_dir, 'workflows.md'),
        File.join(spec_dir, 'glossary.md')
      ] + Dir.glob(File.join(raw_topics_dir, '*.json')).sort + Dir.glob(File.join(raw_posts_dir, '*.jsonl')).sort
    )
  }

  OutputHelpers.write_json(File.join(run_dir, 'manifest.json'), manifest)

  puts "Corpus build complete: #{run_dir}"
  puts "Topics discovered: #{manifest['counts']['topics_discovered']}"
  puts "Topics fetched: #{manifest['counts']['topics_fetched']}"
  puts "Posts fetched: #{manifest['counts']['posts_fetched']}"
end

main if __FILE__ == $PROGRAM_NAME

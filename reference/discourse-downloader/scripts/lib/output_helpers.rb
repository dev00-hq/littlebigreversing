# frozen_string_literal: true

require 'csv'
require 'digest'
require 'fileutils'
require 'json'

module OutputHelpers
  module_function

  def ensure_dir(path)
    FileUtils.mkdir_p(path)
  end

  def write_json(path, object)
    ensure_dir(File.dirname(path))
    File.write(path, JSON.pretty_generate(normalize_encoding(object)))
  end

  def write_jsonl(path, records)
    ensure_dir(File.dirname(path))
    File.open(path, 'w') do |file|
      records.each { |record| file.puts(JSON.generate(normalize_encoding(record))) }
    end
  end

  def write_csv(path, headers, rows)
    ensure_dir(File.dirname(path))
    CSV.open(path, 'w') do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end

  def sha256_for(path)
    Digest::SHA256.file(path).hexdigest
  end

  def normalize_encoding(value)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), memo|
        memo[normalize_encoding(k)] = normalize_encoding(v)
      end
    when Array
      value.map { |item| normalize_encoding(item) }
    when String
      value.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    else
      value
    end
  end
end

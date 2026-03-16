# frozen_string_literal: true

require 'cgi'

module PostExtractors
  module_function

  def extract_links(raw:, cooked:)
    found = []

    raw.to_s.scan(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/i) do |text, url|
      found << { url: url.strip, anchor_text: text.strip }
    end

    cooked.to_s.scan(/<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/im) do |url, html_text|
      found << {
        url: CGI.unescapeHTML(url.strip),
        anchor_text: strip_tags(CGI.unescapeHTML(html_text.to_s)).strip
      }
    end

    dedupe_records(found)
  end

  def extract_code_blocks(raw:, cooked:)
    blocks = []

    raw.to_s.scan(/```([\w+-]*)\n(.*?)```/m) do |language, body|
      blocks << {
        kind: 'fenced',
        language: language.to_s.empty? ? nil : language,
        source: 'raw',
        code: body.to_s.rstrip
      }
    end

    raw.to_s.scan(/`([^`\n]+)`/) do |snippet|
      blocks << {
        kind: 'inline',
        language: nil,
        source: 'raw',
        code: snippet.first.to_s.strip
      }
    end

    cooked_text = cooked.to_s
    pre_sections = []

    cooked_text.scan(/<pre><code(?: class=["'][^"']*language-([^"']+)[^"']*["'])?>(.*?)<\/code><\/pre>/im) do |language, body|
      code = CGI.unescapeHTML(body.to_s).gsub(/\A\n+|\n+\z/, '')
      blocks << {
        kind: 'fenced',
        language: language.to_s.empty? ? nil : language,
        source: 'cooked',
        code: code
      }
      pre_sections << Regexp.last_match(0)
    end

    inline_cooked = cooked_text.dup
    pre_sections.each { |block| inline_cooked.gsub!(block, '') }

    inline_cooked.scan(/<code>(.*?)<\/code>/im) do |snippet|
      code = CGI.unescapeHTML(snippet.first.to_s).strip
      next if code.empty?

      blocks << {
        kind: 'inline',
        language: nil,
        source: 'cooked',
        code: code
      }
    end

    dedupe_records(blocks)
  end

  def extract_attachments(post, cooked:)
    found = []

    Array(post['uploads']).each do |upload|
      found << {
        url: upload['url'] || upload['short_url'],
        filename: upload['original_filename'] || upload['short_path'] || upload['url'],
        mime_type: upload['content_type']
      }
    end

    cooked.to_s.scan(/<(?:a|img)\b[^>]*(?:href|src)=["']([^"']*\/uploads\/[^"']+)["'][^>]*>/im) do |url_match|
      url = CGI.unescapeHTML(url_match.first.to_s.strip)
      found << {
        url: url,
        filename: File.basename(url.split('?').first.to_s),
        mime_type: nil
      }
    end

    dedupe_records(found)
  end

  def strip_tags(text)
    text.gsub(/<[^>]*>/, ' ')
  end

  def dedupe_records(records)
    seen = {}
    records.each_with_object([]) do |record, memo|
      normalized = record.transform_values { |v| v.is_a?(String) ? v.strip : v }
      key = normalized.keys.sort.map { |k| "#{k}=#{normalized[k]}" }.join('|')
      next if seen[key]

      seen[key] = true
      memo << normalized
    end
  end
end

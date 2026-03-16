# frozen_string_literal: true

require 'json'

module ClaimsQuery
  class Error < StandardError
    attr_reader :exit_code

    def initialize(message, exit_code: 1)
      super(message)
      @exit_code = exit_code
    end
  end

  module_function

  def resolve_claims_path(root_dir:, claims_path: nil)
    return claims_path if claims_path && File.file?(claims_path)
    return claims_path if claims_path

    analysis_dir = File.join(File.expand_path(root_dir), 'corpus', 'analysis')
    merged = File.join(analysis_dir, 'stage2_claims_merged.jsonl')
    base = File.join(analysis_dir, 'stage2_claims.jsonl')

    return merged if File.file?(merged)
    return base if File.file?(base)

    raise Error.new("No claims file found. Checked #{merged} and #{base}", exit_code: 1)
  end

  def resolve_topic_cards_path(claims_path)
    analysis_dir = File.dirname(File.expand_path(claims_path))
    merged = File.join(analysis_dir, 'topic_cards_merged.jsonl')
    base = File.join(analysis_dir, 'topic_cards.jsonl')

    return merged if File.file?(merged)
    return base if File.file?(base)

    nil
  end

  def load_topic_titles(cards_path)
    return {} unless cards_path && File.file?(cards_path)

    titles = {}
    File.foreach(cards_path).with_index(1) do |line, line_no|
      stripped = line.strip
      next if stripped.empty?

      row = JSON.parse(stripped)
      next if row['topic_id'].nil?

      titles[row['topic_id'].to_i] = row['title'].to_s
    rescue JSON::ParserError => e
      raise Error.new("Invalid JSON in #{cards_path} at line #{line_no}: #{e.message}", exit_code: 1)
    end

    titles
  end

  def query_claims(path:, filters:, limit: nil)
    raise Error.new("Claims file not found: #{path}", exit_code: 1) unless File.file?(path)

    matched = []
    File.foreach(path).with_index(1) do |line, line_no|
      stripped = line.strip
      next if stripped.empty?

      claim = JSON.parse(stripped)
      next unless claim_matches?(claim, filters)

      matched << claim
    rescue JSON::ParserError => e
      raise Error.new("Invalid JSON in #{path} at line #{line_no}: #{e.message}", exit_code: 1)
    end

    sorted = matched.sort_by do |claim|
      topic_id = normalize_topic_id(claim['topic_id'])
      [
        topic_id.nil? ? 2_147_483_647 : topic_id,
        -claim.fetch('confidence', 0.0).to_f,
        claim.fetch('claim_id', '').to_s
      ]
    end

    return sorted unless limit

    sorted.first(limit)
  end

  def render_jsonl(claims)
    return '' if claims.empty?

    claims.map { |claim| JSON.generate(claim) }.join("\n") + "\n"
  end

  def render_markdown(claims, topic_titles:)
    lines = ['# Claims Query Results']
    grouped = claims.group_by { |claim| normalize_topic_id(claim['topic_id']) }

    grouped.keys.sort_by { |topic_id| topic_id.nil? ? 2_147_483_647 : topic_id }.each do |topic_id|
      title = topic_titles[topic_id] if topic_id
      heading_title = if topic_id.nil?
                        'No Topic'
                      elsif title.nil? || title.empty?
                        "Topic #{topic_id}"
                      else
                        title
                      end

      lines << ''
      heading_id = topic_id.nil? ? 'n/a' : topic_id
      lines << "## Topic #{heading_id}: #{heading_title}"

      grouped[topic_id].each do |claim|
        kind = claim.fetch('claim_kind', 'unknown')
        confidence = format('%.2f', claim.fetch('confidence', 0.0).to_f)
        entities = Array(claim['entities']).join(', ')
        entities = '(none)' if entities.empty?
        claim_text = claim.fetch('claim_text', '').to_s.strip
        claim_text = '(no claim text)' if claim_text.empty?

        provenance = claim['provenance'].is_a?(Hash) ? claim['provenance'] : {}
        source_file = provenance['source_file'] || 'unknown'
        line_no = provenance['line_no'] || '?'
        source_ref = "#{source_file}:#{line_no}"

        lines << "- `#{claim.fetch('claim_id', '-')}` [#{kind}] conf=#{confidence}; entities: #{entities}"
        lines << "  - #{claim_text}"
        lines << "  - provenance: `#{source_ref}`"
      end
    end

    lines.join("\n") + "\n"
  end

  def claim_matches?(claim, filters)
    if filters[:claim_kind]
      return false unless claim.fetch('claim_kind', '').to_s.casecmp(filters[:claim_kind]).zero?
    end

    if filters[:topic_id]
      return false unless normalize_topic_id(claim['topic_id']) == filters[:topic_id]
    end

    if filters[:min_confidence]
      return false unless claim.fetch('confidence', 0.0).to_f >= filters[:min_confidence]
    end

    if filters[:entity_keyword]
      needle = filters[:entity_keyword].downcase
      entities = Array(claim['entities']).map(&:to_s)
      return false unless entities.any? { |entity| entity.downcase.include?(needle) }
    end

    true
  end

  def normalize_topic_id(value)
    return nil if value.nil?
    return value if value.is_a?(Integer)

    stripped = value.to_s.strip
    return nil if stripped.empty?

    Integer(stripped, 10)
  rescue ArgumentError
    nil
  end
end

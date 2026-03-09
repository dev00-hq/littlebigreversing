# frozen_string_literal: true

module EvidenceBuilder
  KEYWORDS = {
    format: %w[hqr ile obl compression offset offsets index indices entry entries checksum constraints],
    script: %w[opcode opcodes decompiler disassembly bytecode script scripts],
    tool: %w[tool editor extractor converter github gitlab repo utility],
    workflow: %w[workflow pipeline steps process how-to modding replace import export],
    pitfall: %w[pitfall break broken crash crashes issue issues limitation warning],
    glossary_candidate: %w[hqr ile obl holomap sendell proto-pack zeelich dinofly]
  }.freeze

  WORKFLOW_HINTS = [
    'how to',
    'replace',
    'without breaking',
    'import',
    'export',
    'workflow',
    'pipeline'
  ].freeze

  module_function

  def build(posts, base_topic_url:)
    posts.each_with_object([]) do |post, evidence|
      text = [post['raw'], post['cooked']].compact.join("\n").downcase

      KEYWORDS.each do |kind, terms|
        matched = terms.select { |term| text.include?(term) }
        next if matched.empty?

        evidence << {
          'kind' => kind.to_s,
          'topic_id' => post['topic_id'],
          'post_id' => post['post_id'],
          'post_number' => post['post_number'],
          'source_url' => "#{base_topic_url}/t/#{post['topic_id']}/#{post['post_number']}",
          'matched_terms' => matched,
          'confidence' => confidence_for(matched.length),
          'excerpt' => excerpt(post['raw']),
          'notes' => notes_for(kind, matched, post, text)
        }
      end
    end
  end

  def notes_for(kind, matched_terms, post, text)
    base = {
      'terms' => matched_terms.uniq.sort
    }

    case kind
    when :format
      base.merge(
        'offset_related' => matched_terms.any? { |term| %w[offset offsets].include?(term) },
        'index_related' => matched_terms.any? { |term| %w[index indices entry entries].include?(term) },
        'compression_related' => matched_terms.include?('compression')
      )
    when :script
      base.merge(
        'opcode_related' => matched_terms.any? { |term| %w[opcode opcodes].include?(term) },
        'decompilation_related' => matched_terms.any? { |term| %w[decompiler disassembly bytecode].include?(term) }
      )
    when :tool
      links = Array(post['links']).map { |link| link['url'] }.compact.uniq.sort
      base.merge(
        'links' => links,
        'repo_links' => links.select { |url| url.include?('github.com') || url.include?('gitlab.com') }
      )
    when :workflow
      base.merge(
        'workflow_hints' => WORKFLOW_HINTS.select { |hint| text.include?(hint) }
      )
    when :pitfall
      base.merge(
        'severity_hints' => matched_terms.select { |term| %w[crash crashes broken break].include?(term) }.uniq.sort
      )
    when :glossary_candidate
      base.merge(
        'candidate_terms' => matched_terms.uniq.sort
      )
    else
      base
    end
  end

  def confidence_for(hit_count)
    [0.4 + (hit_count * 0.15), 0.95].min.round(2)
  end

  def excerpt(text)
    clean = text.to_s.gsub(/\s+/, ' ').strip
    clean[0, 280]
  end
end

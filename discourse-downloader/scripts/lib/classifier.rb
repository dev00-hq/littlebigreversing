# frozen_string_literal: true

require 'yaml'

class TopicClassifier
  DEFAULT_RULES = {
    positive_title_terms: [
      "lba2",
      'lba 2',
      'little big adventure 2',
      "twinsen's odyssey",
      "twinsen’s odyssey",
      'temple of',
      'dinofly',
      'zeelich'
    ],
    positive_body_terms: [
      'island of the celebration',
      'sendell',
      'dark monk',
      'zoe',
      'twinsen odyssey',
      'gas',
      'proto-pack',
      'sprite3d',
      'holomap'
    ],
    negative_title_terms: [
      'lba1',
      'lba 1',
      'little big adventure 1',
      'relentless'
    ],
    negative_body_terms: [
      'citadel island',
      'funfrock',
      'bu',
      'dr funfrock'
    ],
    weights: {
      positive_title: 5,
      positive_body: 4,
      negative_title: -5,
      negative_body: -4
    }
  }.freeze

  def self.from_yaml(path)
    return new(DEFAULT_RULES) unless path

    loaded = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
    merged = deep_merge(DEFAULT_RULES, symbolize_keys(loaded || {}))
    new(merged)
  end

  def self.deep_merge(base, other)
    return base unless other

    base.merge(other) do |_k, base_value, other_value|
      if base_value.is_a?(Hash) && other_value.is_a?(Hash)
        deep_merge(base_value, other_value)
      else
        other_value
      end
    end
  end

  def self.symbolize_keys(object)
    case object
    when Hash
      object.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = symbolize_keys(v) }
    when Array
      object.map { |value| symbolize_keys(value) }
    else
      object
    end
  end

  def initialize(rules = DEFAULT_RULES)
    @rules = rules
  end

  def classify(title:, first_post_raw:)
    title_text = normalize(title)
    body_text = normalize(first_post_raw)

    score = 0
    matched_rules = []

    score += evaluate_terms(
      @rules[:positive_title_terms],
      title_text,
      @rules[:weights][:positive_title],
      'positive_title',
      matched_rules
    )

    score += evaluate_terms(
      @rules[:positive_body_terms],
      body_text,
      @rules[:weights][:positive_body],
      'positive_body',
      matched_rules
    )

    score += evaluate_terms(
      @rules[:negative_title_terms],
      title_text,
      @rules[:weights][:negative_title],
      'negative_title',
      matched_rules
    )

    score += evaluate_terms(
      @rules[:negative_body_terms],
      body_text,
      @rules[:weights][:negative_body],
      'negative_body',
      matched_rules
    )

    {
      score: score,
      label: label_for(score),
      matched_rules: matched_rules
    }
  end

  private

  def normalize(text)
    text.to_s.downcase
  end

  def evaluate_terms(terms, text, weight, rule_name, matched_rules)
    hit_terms = Array(terms).select { |term| term_matches?(text, term) }
    return 0 if hit_terms.empty?

    matched_rules << {
      rule: rule_name,
      weight: weight,
      terms: hit_terms
    }
    weight
  end

  def term_matches?(text, term)
    normalized_term = normalize(term)
    return false if normalized_term.empty?

    escaped = Regexp.escape(normalized_term).gsub('\\ ', '\\s+')
    pattern = /(?<![[:alnum:]])#{escaped}(?![[:alnum:]])/
    !text.match(pattern).nil?
  end

  def label_for(score)
    return 'lba2' if score >= 5
    return 'mixed' if score >= 1

    'undetermined'
  end
end

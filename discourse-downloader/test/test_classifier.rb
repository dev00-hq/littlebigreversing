# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../scripts/lib/classifier'

class TopicClassifierTest < Minitest::Test
  def setup
    @classifier = TopicClassifier.new
  end

  def test_classifies_lba2_from_title
    result = @classifier.classify(
      title: 'LBA2 outdoor scene modding',
      first_post_raw: 'generic content'
    )

    assert_equal 'lba2', result[:label]
    assert_operator result[:score], :>=, 5
  end

  def test_classifies_lba2_from_spaced_title_variant
    result = @classifier.classify(
      title: 'Using LBA 2 as a Visual Novel engine',
      first_post_raw: 'generic content'
    )

    assert_equal 'lba2', result[:label]
    assert_operator result[:score], :>=, 5
  end

  def test_classifies_mixed_when_positive_and_negative_signals_collide
    result = @classifier.classify(
      title: 'Relentless vs LBA2 scripting differences',
      first_post_raw: 'opcode and sendell notes'
    )

    assert_equal 'mixed', result[:label]
    assert_equal 4, result[:score]
  end

  def test_classifies_undetermined_for_lba1_only_signal
    result = @classifier.classify(
      title: 'LBA1 relentless graphics notes',
      first_post_raw: 'funfrock bu citadel island'
    )

    assert_equal 'undetermined', result[:label]
    assert_operator result[:score], :<=, 0
  end

  def test_classifies_lba2_from_new_title_tokens
    result = @classifier.classify(
      title: 'Zeelich Temple of Sendell - Dinofly behavior',
      first_post_raw: 'generic content'
    )

    assert_equal 'lba2', result[:label]
    assert_operator result[:score], :>=, 5
  end

  def test_does_not_match_short_negative_term_inside_word
    result = @classifier.classify(
      title: 'LBA 2 scene notes',
      first_post_raw: 'Background image tests and buffers'
    )

    assert_equal 'lba2', result[:label]
    matched_negative = result[:matched_rules].select { |rule| rule[:rule] == 'negative_body' }
    assert_equal [], matched_negative
  end
end

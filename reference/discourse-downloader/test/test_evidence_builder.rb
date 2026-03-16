# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../scripts/lib/evidence_builder'

class EvidenceBuilderTest < Minitest::Test
  def test_builds_structured_notes
    posts = [
      {
        'topic_id' => 10,
        'post_id' => 22,
        'post_number' => 3,
        'raw' => <<~RAW,
          HQR offsets and entry indices:
          how to replace an entry without breaking indices.
          Tool repo: https://github.com/example/lba-tool
          opcode decompiler notes.
          Warning: crash when checksum is invalid.
        RAW
        'cooked' => '',
        'links' => [
          { 'url' => 'https://github.com/example/lba-tool', 'anchor_text' => 'tool' }
        ]
      }
    ]

    rows = EvidenceBuilder.build(posts, base_topic_url: 'https://forum.magicball.net')
    by_kind = rows.each_with_object({}) { |row, memo| memo[row['kind']] = row }

    assert by_kind.key?('format')
    assert by_kind.key?('script')
    assert by_kind.key?('tool')
    assert by_kind.key?('workflow')
    assert by_kind.key?('pitfall')
    assert by_kind.key?('glossary_candidate')

    assert_equal true, by_kind['format']['notes']['offset_related']
    assert_includes by_kind['tool']['notes']['repo_links'], 'https://github.com/example/lba-tool'
    assert_includes by_kind['workflow']['notes']['workflow_hints'], 'replace'
    assert_includes by_kind['pitfall']['notes']['severity_hints'], 'crash'
  end
end

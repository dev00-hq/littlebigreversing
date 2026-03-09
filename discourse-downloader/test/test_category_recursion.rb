# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../scripts/build_corpus'

class CategoryRecursionTest < Minitest::Test
  class FakeClient
    def initialize(categories)
      @categories = categories
    end

    def get_json(path)
      raise "Unexpected path #{path}" unless path == '/site.json'

      { 'categories' => @categories }
    end
  end

  def test_parse_category_url_extracts_id
    parsed = parse_category_url('https://forum.magicball.net/c/lba-modifications/10')

    assert_equal 10, parsed[:category_id]
    assert_equal '/c/lba-modifications/10', parsed[:path]
  end

  def test_resolve_category_targets_recurses_children
    seed = parse_category_url('https://forum.magicball.net/c/lba-modifications/10')
    client = FakeClient.new(
      [
        { 'id' => 10, 'slug' => 'lba-modifications' },
        { 'id' => 11, 'slug' => 'sub-a', 'parent_category_id' => 10 },
        { 'id' => 12, 'slug' => 'sub-b', 'parent_category_id' => 11 }
      ]
    )

    resolved = resolve_category_targets(client, [seed], true, false)
    ids = resolved.map { |row| row[:category_id] }

    assert_equal [10, 11, 12], ids
    assert_equal '/c/11', resolved[1][:path]
    assert_equal 10, resolved[2][:source_category_id]
  end

  def test_resolve_category_targets_without_recursion
    seed = parse_category_url('https://forum.magicball.net/c/lba-modifications/10')
    client = FakeClient.new([])

    resolved = resolve_category_targets(client, [seed], false, false)

    assert_equal [10], resolved.map { |row| row[:category_id] }
  end
end

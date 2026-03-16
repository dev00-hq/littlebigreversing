# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../scripts/lib/post_extractors'

class PostExtractorsTest < Minitest::Test
  def test_extract_links_from_raw_and_cooked
    raw = "See [docs](https://example.com/docs)."
    cooked = '<p><a href="https://forum.magicball.net/t/10">thread</a></p>'

    links = PostExtractors.extract_links(raw: raw, cooked: cooked)

    assert_includes links, { url: 'https://example.com/docs', anchor_text: 'docs' }
    assert_includes links, { url: 'https://forum.magicball.net/t/10', anchor_text: 'thread' }
  end

  def test_extract_code_blocks
    raw = "```ruby\nputs :ok\n```\nInline `x = 1`"
    cooked = '<pre><code class="lang-ruby">puts :ok</code></pre><code>y = 2</code>'

    blocks = PostExtractors.extract_code_blocks(raw: raw, cooked: cooked)

    assert blocks.any? { |b| b[:kind] == 'fenced' && b[:code].include?('puts :ok') }
    assert blocks.any? { |b| b[:kind] == 'inline' && b[:code] == 'x = 1' }
    assert blocks.any? { |b| b[:kind] == 'inline' && b[:code] == 'y = 2' }
  end

  def test_extract_attachments
    post = {
      'uploads' => [
        {
          'url' => '/uploads/default/original/1X/image.png',
          'original_filename' => 'image.png',
          'content_type' => 'image/png'
        }
      ]
    }
    cooked = '<p><a href="/uploads/default/original/1X/file.zip">file.zip</a></p>'

    attachments = PostExtractors.extract_attachments(post, cooked: cooked)

    assert attachments.any? { |a| a[:url].include?('/uploads/default/original/1X/image.png') }
    assert attachments.any? { |a| a[:url].include?('/uploads/default/original/1X/file.zip') }
  end
end

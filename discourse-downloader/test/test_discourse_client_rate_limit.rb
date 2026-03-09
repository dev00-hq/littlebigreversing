# frozen_string_literal: true

require 'minitest/autorun'
require 'net/http'
require_relative '../scripts/lib/discourse_client'

class DiscourseClientRateLimitTest < Minitest::Test
  class ScriptedClient < DiscourseClient
    attr_reader :sleep_calls, :request_count

    def initialize(responses:, **kwargs)
      @responses = responses
      @sleep_calls = []
      @request_count = 0
      super(**kwargs)
    end

    private

    def perform_request(_http, _req)
      @request_count += 1
      raise 'Missing scripted response' if @responses.empty?

      @responses.shift
    end

    def sleep_seconds(seconds)
      return if seconds.nil? || seconds <= 0

      @sleep_calls << seconds
    end
  end

  def build_response(code, body: '', headers: {})
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    response = klass.new('1.1', code.to_s, "status #{code}")
    headers.each { |key, value| response[key] = value }
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def test_retries_429_with_retry_after
    client = ScriptedClient.new(
      base_url: 'https://example.com',
      responses: [
        build_response(429, body: 'rate', headers: { 'Retry-After' => '2' }),
        build_response(200, body: 'ok')
      ],
      request_retries: 2,
      min_delay_ms: 0,
      max_delay_ms: 0,
      backoff_base_ms: 300
    )

    body = client.get('/path')

    assert_equal 'ok', body
    assert_equal 2, client.request_count
    assert_includes client.sleep_calls, 2.0
  end

  def test_retries_503_without_retry_after
    client = ScriptedClient.new(
      base_url: 'https://example.com',
      responses: [
        build_response(503, body: 'busy'),
        build_response(200, body: 'ok')
      ],
      request_retries: 2,
      min_delay_ms: 0,
      max_delay_ms: 0,
      backoff_base_ms: 300
    )

    body = client.get('/path')

    assert_equal 'ok', body
    assert_equal 2, client.request_count
    assert_includes client.sleep_calls, 0.3
  end
end

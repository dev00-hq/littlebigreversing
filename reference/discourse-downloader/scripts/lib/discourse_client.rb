# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

class DiscourseClient
  DEFAULT_OPEN_TIMEOUT = 15
  DEFAULT_READ_TIMEOUT = 45
  DEFAULT_WRITE_TIMEOUT = 45
  DEFAULT_REQUEST_RETRIES = 5
  DEFAULT_MIN_DELAY_MS = 800
  DEFAULT_MAX_DELAY_MS = 1300
  DEFAULT_BACKOFF_BASE_MS = 500
  RETRYABLE_HTTP_CODES = [429, 502, 503, 504].freeze

  attr_reader :base_url

  def initialize(base_url:, api_key: nil, api_user: nil, username: nil, password: nil, verbose: false,
                 open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                 write_timeout: DEFAULT_WRITE_TIMEOUT, request_retries: DEFAULT_REQUEST_RETRIES,
                 min_delay_ms: DEFAULT_MIN_DELAY_MS, max_delay_ms: DEFAULT_MAX_DELAY_MS,
                 backoff_base_ms: DEFAULT_BACKOFF_BASE_MS)
    @base_url = normalize_base_url(base_url)
    @api_key = api_key
    @api_user = api_user
    @username = username
    @password = password
    @verbose = verbose
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @write_timeout = write_timeout
    @request_retries = request_retries
    @min_delay_ms = [min_delay_ms.to_i, 0].max
    @max_delay_ms = [max_delay_ms.to_i, @min_delay_ms].max
    @backoff_base_ms = [backoff_base_ms.to_i, 1].max
    @cookies = {}

    if @username || @password
      raise ArgumentError, 'Both username and password are required' unless @username && @password

      login_session
    end
  end

  def get(path_or_url, headers: {})
    request(:get, path_or_url, headers: headers)
  end

  def get_json(path_or_url, headers: {})
    JSON.parse(get(path_or_url, headers: headers.merge('Accept' => 'application/json')))
  end

  def post_form(path_or_url, form, headers: {})
    request(:post, path_or_url, form: form, headers: headers)
  end

  private

  def normalize_base_url(url)
    uri = URI.parse(url)
    raise ArgumentError, "Invalid base URL: #{url}" unless uri.is_a?(URI::HTTP) && uri.host

    "#{uri.scheme}://#{uri.host}"
  end

  def absolute_url(path_or_url)
    uri = URI.parse(path_or_url)
    return path_or_url if uri.is_a?(URI::HTTP)

    URI.join(@base_url, path_or_url).to_s
  end

  def login_session
    log("Authenticating as #{@username}")

    csrf_data = get_json('/session/csrf', headers: { 'Accept' => 'application/json' })
    csrf_token = csrf_data['csrf']
    raise 'Failed to fetch CSRF token' unless csrf_token

    login_data = JSON.parse(
      post_form(
        '/session.json',
        {
          'login' => @username,
          'password' => @password
        },
        headers: {
          'Accept' => 'application/json',
          'X-Requested-With' => 'XMLHttpRequest',
          'X-CSRF-Token' => csrf_token
        }
      )
    )

    raise "Login failed: #{login_data['error']}" if login_data['error']
    raise 'Login requires second factor; non-interactive login is unsupported' if login_data['requires_second_factor']

    log("Authenticated as #{@username}")
  end

  def add_query_auth(url)
    return url unless @api_key && @api_user

    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query || '')
    params << ['api_key', @api_key]
    params << ['api_user', @api_user]
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  def cookie_header
    @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
  end

  def store_cookies(response)
    set_cookie_headers = response.get_fields('set-cookie') || []
    set_cookie_headers.each do |header|
      pair = header.split(';', 2).first
      name, value = pair.split('=', 2)
      next unless name && value

      @cookies[name] = value
    end
  end

  def request(method, path_or_url, form: nil, headers: {}, redirect_limit: 5)
    url = add_query_auth(absolute_url(path_or_url))
    uri = URI.parse(url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.write_timeout = @write_timeout if http.respond_to?(:write_timeout=)

    req = if method == :post
            Net::HTTP::Post.new(uri.request_uri)
          else
            Net::HTTP::Get.new(uri.request_uri)
          end

    headers.each { |k, v| req[k] = v }
    req['Cookie'] = cookie_header unless @cookies.empty?
    req.set_form_data(form) if form

    attempts = 0

    loop do
      sleep_seconds(request_delay_seconds)
      attempts += 1

      begin
        response = perform_request(http, req)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError => e
        if attempts <= @request_retries
          sleep_seconds(backoff_delay_seconds(attempts))
          next
        end

        raise "Request failed for #{url} after #{attempts} attempt(s): #{e.class} #{e.message}"
      end

      store_cookies(response)

      if response.is_a?(Net::HTTPRedirection)
        raise "Too many redirects for #{url}" if redirect_limit <= 0

        location = response['location']
        redirected_url = URI.join(url, location).to_s
        return request(:get, redirected_url, headers: headers, redirect_limit: redirect_limit - 1)
      end

      if retryable_response?(response) && attempts <= @request_retries
        sleep_seconds(retry_after_seconds(response) || backoff_delay_seconds(attempts))
        next
      end

      unless response.is_a?(Net::HTTPSuccess)
        snippet = response.body.to_s[0, 300]
        raise "HTTP #{response.code} for #{url}: #{snippet}"
      end

      return response.body
    end
  end

  def perform_request(http, req)
    http.request(req)
  end

  def request_delay_seconds
    return 0 if @max_delay_ms <= 0
    return @min_delay_ms.to_f / 1000.0 if @max_delay_ms <= @min_delay_ms

    rand(@min_delay_ms..@max_delay_ms).to_f / 1000.0
  end

  def backoff_delay_seconds(attempt)
    attempt_number = [attempt.to_i, 1].max
    (@backoff_base_ms.to_f / 1000.0) * (2**(attempt_number - 1))
  end

  def retryable_response?(response)
    RETRYABLE_HTTP_CODES.include?(response.code.to_i)
  end

  def retry_after_seconds(response)
    raw = response['Retry-After']
    return nil if raw.nil? || raw.strip.empty?

    raw.to_f
  rescue StandardError
    nil
  end

  def sleep_seconds(seconds)
    return if seconds.nil? || seconds <= 0

    sleep(seconds)
  end

  def log(message)
    puts message if @verbose
  end
end

# frozen_string_literal: true

module ConfigLoader
  module_function

  def load_config(path)
    config = {
      api_key: nil,
      api_user: nil,
      username: nil,
      password: nil
    }

    return config unless path

    expanded = File.expand_path(path)
    return config unless File.file?(expanded)

    lines = []

    File.readlines(expanded).each do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?('#')

      if stripped =~ /\A([A-Z_]+)\s*=\s*(.+)\z/
        key = Regexp.last_match(1)
        value = Regexp.last_match(2).strip
        value = Regexp.last_match(1) if value =~ /\A"(.*)"\z/
        value = Regexp.last_match(1) if value =~ /\A'(.*)'\z/

        case key
        when 'API_KEY'
          config[:api_key] = value
        when 'API_USER'
          config[:api_user] = value
        when 'USERNAME', 'USER', 'LOGIN', 'EMAIL'
          config[:username] = value
        when 'PASSWORD', 'PASS'
          config[:password] = value
        end

        next
      end

      lines << stripped
    end

    if config[:username].nil? && lines.length >= 2
      config[:username] = lines[0]
      config[:password] = lines[1]
    end

    config
  end
end

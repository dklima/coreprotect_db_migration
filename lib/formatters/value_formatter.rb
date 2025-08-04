# frozen_string_literal: true

require "base64"
require "json"

class ValueFormatter
  def self.format_for_mysql(value)
    return value.to_json unless value.is_a?(String)

    "FROM_BASE64('#{Base64.strict_encode64(value)}')"
  end
end

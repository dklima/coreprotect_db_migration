# frozen_string_literal: true

require_relative 'my_connection'
require_relative 'lite_connection'

def my_conn
  @my_conn ||= MyConnection.call
end

def lite_conn
  @lite_conn ||= LiteConnection.call
end


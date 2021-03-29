# frozen_string_literal: true

require 'mysql2'

# Connect to MySQL server
class MyConnection
  def self.call
    Mysql2::Client.new(
      host: ENV.fetch('MYSQL_HOST'),
      username: ENV.fetch('MYSQL_USER'),
      password: ENV.fetch('MYSQL_PASS'),
      port: ENV.fetch('MYSQL_PORT'),
      database: ENV.fetch('MYSQL_DATABASE'),
      encoding: 'utf8mb4',
      read_timeout: 3600,
      write_timeout: 3600,
      connect_timeout: 3600,
      reconnect: true
    )
  end
end

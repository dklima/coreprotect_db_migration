# frozen_string_literal: true

require 'sqlite3'

# Connect to the SQLite database file
class LiteConnection
  def self.call
    SQLite3::Database.new ENV.fetch('SQLITE_DATABASE')
  end
end

# frozen_string_literal: true

# Configuration manager following Single Responsibility Principle
class Configuration
  REQUIRED_ENV_VARS = %w[
    MYSQL_HOST MYSQL_USER MYSQL_PASS MYSQL_PORT MYSQL_DATABASE
    SQLITE_DATABASE OFFSET
  ].freeze

  def self.validate_environment
    return if File.exist?(".env")

    warn ".env file not found."
    warn 'Please create it based on _env file and source it with "source .env" command.'
    warn "For more details, check README.md file."
    exit 1
  end

  def self.batch_size
    @batch_size ||= ENV.fetch("OFFSET", "10000").to_i
  end

  def self.mysql_database
    @mysql_database ||= ENV.fetch("MYSQL_DATABASE")
  end
end

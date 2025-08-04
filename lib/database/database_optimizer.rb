# frozen_string_literal: true

require_relative "../configuration/configuration"

class DatabaseOptimizer
  def initialize(mysql_connection)
    @mysql_connection = mysql_connection
  end

  def prepare_for_migration
    optimize_database_encoding
    disable_constraints_and_checks
  end

  def finalize_migration
    enable_constraints_and_checks
  end

  private

  def optimize_database_encoding
    @mysql_connection.query(
      "ALTER DATABASE #{Configuration.mysql_database} " \
      "CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;"
    )
  end

  def disable_constraints_and_checks
    @mysql_connection.query("SET FOREIGN_KEY_CHECKS=0;")
    @mysql_connection.query("SET UNIQUE_CHECKS=0;")
    @mysql_connection.query("SET autocommit=0")
  end

  def enable_constraints_and_checks
    @mysql_connection.query("SET FOREIGN_KEY_CHECKS=1;")
    @mysql_connection.query("SET UNIQUE_CHECKS=1;")
    @mysql_connection.query("SET autocommit=1")
  end
end

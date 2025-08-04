# frozen_string_literal: true

require_relative "../error_handling/migration_error"

class SchemaValidator
  def initialize(mysql_connection, sqlite_connection)
    @mysql_connection = mysql_connection
    @sqlite_connection = sqlite_connection
  end

  def validate_table_schema(table_name)
    sqlite_columns = extract_sqlite_columns(table_name)
    mysql_columns = extract_mysql_columns(table_name)

    missing_columns = find_missing_columns(sqlite_columns, mysql_columns)
    extra_columns = find_extra_columns(sqlite_columns, mysql_columns)

    return true if missing_columns.empty? && extra_columns.empty?

    raise SchemaMismatchError.new(table_name, missing_columns, extra_columns)
  end

  def table_exists_in_mysql?(table_name)
    result = @mysql_connection.query(
      "SELECT COUNT(*) as count FROM information_schema.tables
       WHERE table_schema = DATABASE() AND table_name = '#{table_name}'"
    )
    result.first["count"] > 0
  end

  def get_compatible_columns(table_name)
    sqlite_columns = extract_sqlite_columns(table_name)
    mysql_columns = extract_mysql_columns(table_name)

    # Return only columns that exist in both schemas
    compatible_columns = sqlite_columns & mysql_columns

    # Handle special case: SQLite rowid -> MySQL id mapping
    if sqlite_columns.include?("id") && mysql_columns.include?("id")
      compatible_columns = compatible_columns.map { |col| col == "id" ? "rowid" : col }
    end

    compatible_columns
  end

  def analyze_schema_differences(table_name)
    return { compatible: false, reason: "Table does not exist in MySQL" } unless table_exists_in_mysql?(table_name)

    sqlite_columns = extract_sqlite_columns(table_name)
    mysql_columns = extract_mysql_columns(table_name)

    missing_columns = find_missing_columns(sqlite_columns, mysql_columns)
    extra_columns = find_extra_columns(sqlite_columns, mysql_columns)
    compatible_columns = sqlite_columns & mysql_columns

    {
      compatible: missing_columns.empty?,
      sqlite_columns: sqlite_columns,
      mysql_columns: mysql_columns,
      missing_columns: missing_columns,
      extra_columns: extra_columns,
      compatible_columns: compatible_columns,
      compatibility_percentage: calculate_compatibility_percentage(sqlite_columns, compatible_columns)
    }
  end

  private

  def extract_sqlite_columns(table_name)
    # Get column names from SQLite, replacing 'id' with 'rowid' for consistency
    result = @sqlite_connection.prepare("SELECT * FROM #{table_name} LIMIT 1")
    columns = result.columns.map { |column| column == "id" ? "rowid" : column }
    result.close
    columns
  rescue SQLite3::Exception => e
    raise MigrationError, "Failed to extract SQLite columns for #{table_name}: #{e.message}"
  end

  def extract_mysql_columns(table_name)
    result = @mysql_connection.query(
      "SELECT COLUMN_NAME
       FROM information_schema.columns
       WHERE table_schema = DATABASE() AND table_name = '#{table_name}'
       ORDER BY ordinal_position"
    )
    result.map { |row| row["COLUMN_NAME"] }
  rescue Mysql2::Error => e
    raise MigrationError, "Failed to extract MySQL columns for #{table_name}: #{e.message}"
  end

  def find_missing_columns(sqlite_columns, mysql_columns)
    sqlite_columns - mysql_columns
  end

  def find_extra_columns(sqlite_columns, mysql_columns)
    mysql_columns - sqlite_columns
  end

  def calculate_compatibility_percentage(sqlite_columns, compatible_columns)
    return 0 if sqlite_columns.empty?

    (compatible_columns.size.to_f / sqlite_columns.size * 100).round(2)
  end
end

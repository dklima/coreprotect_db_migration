# frozen_string_literal: true

require_relative "../configuration/configuration"
require_relative "../reporting/progress_reporter"
require_relative "../formatters/value_formatter"
require_relative "../error_handling/table_migration_error"
require_relative "../error_handling/migration_error"

class TableProcessor
  TABLES_WITH_NULL_ID = %w[co_art_map co_blockdata_map co_entity_map co_material_map co_world].freeze

  def initialize(mysql_connection, sqlite_connection, schema_validator: nil, recovery_manager: nil)
    @mysql_connection = mysql_connection
    @sqlite_connection = sqlite_connection
    @sqlite_connection.results_as_hash = true
    @schema_validator = schema_validator
    @recovery_manager = recovery_manager
  end

  def process_table(table_name)
    validate_schema_if_available(table_name)
    prepare_table(table_name)

    columns = extract_columns(table_name)
    total_rows = count_rows(table_name)

    reporter = ProgressReporter.new(table_name, total_rows)
    reporter.report_start

    migrate_data(table_name, columns, total_rows, reporter)
    update_rowid_if_needed(table_name)

    reporter.report_completion
    :completed
  rescue SchemaMismatchError => e
    handle_schema_mismatch(table_name, e)
  rescue StandardError => e
    handle_table_error(table_name, e)
  end

  def process_table_with_compatible_columns(table_name)
    return process_table(table_name) unless @schema_validator

    analysis = @schema_validator.analyze_schema_differences(table_name)
    return :skipped unless analysis[:compatible] || analysis[:compatibility_percentage] > 0

    puts "Migrating only compatible columns for #{table_name} (#{analysis[:compatibility_percentage]}% compatible)"

    prepare_table(table_name)
    columns = analysis[:compatible_columns].join(",")
    total_rows = count_rows(table_name)

    reporter = ProgressReporter.new(table_name, total_rows)
    reporter.report_start

    migrate_data(table_name, columns, total_rows, reporter)
    update_rowid_if_needed(table_name)

    reporter.report_completion
    :completed_partial
  rescue StandardError => e
    handle_table_error(table_name, e)
  end

  def list_tables
    @sqlite_connection.execute('SELECT name FROM sqlite_master WHERE type="table" ORDER BY name;')
  end

  private

  def validate_schema_if_available(table_name)
    return unless @schema_validator

    @schema_validator.validate_table_schema(table_name)
  end

  def handle_schema_mismatch(table_name, error)
    return raise error unless @recovery_manager

    action = @recovery_manager.handle_schema_mismatch(table_name, error)

    case action
    when :continue
      :skipped
    when :skip_columns
      process_table_with_compatible_columns(table_name)
    when :retry
      process_table(table_name)
    else
      raise error
    end
  end

  def handle_table_error(table_name, error)
    detailed_error = TableMigrationError.new("Failed to migrate table #{table_name}: #{error.message}")

    return raise detailed_error unless @recovery_manager

    action = @recovery_manager.handle_table_error(table_name, detailed_error)

    case action
    when :continue
      :skipped
    when :retry
      process_table(table_name)
    else
      raise detailed_error
    end
  end

  def prepare_table(table_name)
    printf "Truncating #{table_name}... "

    begin
      @mysql_connection.query("TRUNCATE TABLE `#{table_name}`")
      @mysql_connection.query(
        "ALTER TABLE `#{table_name}` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
      )

      # Special handling for co_item table
      if table_name == "co_item"
        @mysql_connection.query("ALTER TABLE `co_item` CHANGE `data` `data` MEDIUMBLOB NULL;")
      end

      puts "done"
    rescue Mysql2::Error => e
      puts "failed"
      raise MigrationError, "Failed to prepare table #{table_name}: #{e.message}"
    end
  end

  def extract_columns(table_name)
    statement = @sqlite_connection.prepare("SELECT * FROM #{table_name} LIMIT 1")
    columns = statement.columns

    if columns.nil?
      raise MigrationError, "Failed to extract columns for #{table_name}: columns returned nil"
    end

    columns.map { |column| column == "id" ? "rowid" : column }
           .join(",")
  rescue SQLite3::Exception => e
    raise MigrationError, "Failed to extract columns for #{table_name}: #{e.message}"
  end

  def count_rows(table_name)
    @sqlite_connection.execute("SELECT COUNT(*) FROM #{table_name}")[0][0]
  rescue SQLite3::Exception => e
    raise MigrationError, "Failed to count rows for #{table_name}: #{e.message}"
  end

  def migrate_data(table_name, columns, total_rows, reporter)
    current_offset = 0
    batch_size = Configuration.batch_size

    while current_offset < total_rows
      rows = fetch_batch(table_name, current_offset, batch_size)
      insert_batch(table_name, columns, rows) unless rows.empty?

      current_offset += batch_size
      processed_rows = [ current_offset, total_rows ].min
      reporter.report_progress(processed_rows)
    end
  rescue StandardError => e
    raise MigrationError, "Failed to migrate data for #{table_name} at offset #{current_offset}: #{e.message}"
  end

  def fetch_batch(table_name, offset, limit)
    @sqlite_connection.execute("SELECT * FROM #{table_name} LIMIT #{limit} OFFSET #{offset}")
  rescue SQLite3::Exception => e
    raise MigrationError, "Failed to fetch batch for #{table_name} at offset #{offset}: #{e.message}"
  end

  def insert_batch(table_name, columns, rows)
    values_sql = build_values_sql(rows)
    return if values_sql.empty?

    @mysql_connection.query("START TRANSACTION")

    begin
      @mysql_connection.query("INSERT INTO #{table_name} (#{columns}) VALUES #{values_sql}")
      @mysql_connection.query("COMMIT")
    rescue Mysql2::Error => e
      @mysql_connection.query("ROLLBACK")

      # Enhanced error message for schema-related issues
      if e.message.include?("Unknown column")
        column_match = e.message.match(/'([^']+)' in 'field list'/)
        column_name = column_match ? column_match[1] : "unknown"
        raise SchemaMismatchError.new(table_name, [ column_name ], [])
      end

      raise MigrationError, "Failed to insert batch for #{table_name}: #{e.message}"
    end
  end

  def build_values_sql(rows)
    rows.map do |row|
      formatted_values = row.map { |_field, value| ValueFormatter.format_for_mysql(value) }
      "(#{formatted_values.join(', ')})"
    end.join(", ")
  end

  def update_rowid_if_needed(table_name)
    return unless TABLES_WITH_NULL_ID.include?(table_name)

    puts "Updating id column with rowid value..."
    @mysql_connection.query("UPDATE #{table_name} SET id = rowid WHERE id IS NULL;")
  rescue Mysql2::Error => e
    raise MigrationError, "Failed to update rowid for #{table_name}: #{e.message}"
  end
end

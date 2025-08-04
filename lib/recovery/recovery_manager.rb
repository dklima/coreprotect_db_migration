# frozen_string_literal: true

require_relative "../error_handling/migration_error"

class RecoveryManager
  RECOVERY_ACTIONS = {
    skip: "Skip this table and continue with next table",
    skip_column: "Skip problematic columns and migrate compatible data only",
    retry: "Retry the migration for this table",
    abort: "Stop the migration process"
  }.freeze

  def initialize(interactive_mode: true)
    @interactive_mode = interactive_mode
    @skipped_tables = []
    @failed_tables = []
    @recovery_log = []
  end

  def handle_table_error(table_name, error)
    log_error(table_name, error)

    if @interactive_mode
      handle_interactive_recovery(table_name, error)
    else
      handle_automatic_recovery(table_name, error)
    end
  end

  def handle_schema_mismatch(table_name, schema_mismatch_error)
    log_error(table_name, schema_mismatch_error)

    if @interactive_mode
      handle_interactive_schema_recovery(table_name, schema_mismatch_error)
    else
      handle_automatic_schema_recovery(table_name, schema_mismatch_error)
    end
  end

  def recovery_summary
    {
      skipped_tables: @skipped_tables,
      failed_tables: @failed_tables,
      recovery_log: @recovery_log,
      total_issues: @recovery_log.size
    }
  end

  def has_skipped_tables?
    !@skipped_tables.empty?
  end

  def has_failed_tables?
    !@failed_tables.empty?
  end

  private

  def handle_interactive_recovery(table_name, error)
    puts "\n" + "="*60
    puts "TABLE MIGRATION ERROR: #{table_name}"
    puts "="*60
    puts "Error: #{error.message}"
    puts

    if error.is_a?(SchemaMismatchError)
      handle_interactive_schema_recovery(table_name, error)
    else
      action = prompt_for_recovery_action(table_name)
      execute_recovery_action(table_name, action, error)
    end
  end

  def handle_interactive_schema_recovery(table_name, schema_error)
    puts "SCHEMA INCOMPATIBILITY DETECTED:"
    puts "- Columns missing in MySQL: #{schema_error.missing_columns.join(', ')}" unless schema_error.missing_columns.empty?
    puts "- Extra columns in SQLite: #{schema_error.extra_columns.join(', ')}" unless schema_error.extra_columns.empty?
    puts

    puts "Available options:"
    puts "1. [skip] Skip this table completely"
    puts "2. [skip_column] Migrate only compatible columns"
    puts "3. [retry] Try again (if you fixed the MySQL schema)"
    puts "4. [abort] Stop the migration"
    puts

    action = prompt_for_action("Choose an action (1-4): ")
    execute_recovery_action(table_name, action, schema_error)
  end

  def handle_automatic_recovery(table_name, error)
    if error.is_a?(SchemaMismatchError)
      puts "Schema mismatch detected for #{table_name}. Automatically skipping table."
      execute_recovery_action(table_name, :skip, error)
    else
      puts "Non-recoverable error for #{table_name}: #{error.message}"
      execute_recovery_action(table_name, :abort, error)
    end
  end

  def handle_automatic_schema_recovery(table_name, schema_error)
    if schema_error.missing_columns.empty?
      puts "Extra columns detected in #{table_name}. Migrating only compatible columns."
      execute_recovery_action(table_name, :skip_column, schema_error)
    else
      puts "Missing columns detected in #{table_name}. Skipping table."
      execute_recovery_action(table_name, :skip, schema_error)
    end
  end

  def prompt_for_recovery_action(table_name)
    puts "Recovery options for #{table_name}:"
    RECOVERY_ACTIONS.each_with_index do |(action, description), index|
      puts "#{index + 1}. [#{action}] #{description}"
    end
    puts

    prompt_for_action("Choose an action (1-#{RECOVERY_ACTIONS.size}): ")
  end

  def prompt_for_action(prompt_text)
    print prompt_text
    input = ($stdin.gets || "").chomp.strip.downcase

    case input
    when "1", "skip", "s"
      :skip
    when "2", "skip_column", "sc"
      :skip_column
    when "3", "retry", "r"
      :retry
    when "4", "abort", "a"
      :abort
    else
      puts "Invalid option. Please try again."
      prompt_for_action(prompt_text)
    end
  end

  def execute_recovery_action(table_name, action, error)
    case action
    when :skip
      skip_table(table_name, error)
    when :skip_column
      mark_for_column_skip(table_name, error)
    when :retry
      mark_for_retry(table_name, error)
    when :abort
      abort_migration(table_name, error)
    end
  end

  def skip_table(table_name, error)
    @skipped_tables << table_name
    @recovery_log << {
      table: table_name,
      action: :skip,
      error: error.class.name,
      message: error.message,
      timestamp: Time.now
    }

    puts "Table #{table_name} was skipped. Continuing with next table."
    :continue
  end

  def mark_for_column_skip(table_name, error)
    @recovery_log << {
      table: table_name,
      action: :skip_column,
      error: error.class.name,
      message: error.message,
      timestamp: Time.now
    }

    puts "Migrating only compatible columns for #{table_name}."
    :skip_columns
  end

  def mark_for_retry(table_name, error)
    @recovery_log << {
      table: table_name,
      action: :retry,
      error: error.class.name,
      message: error.message,
      timestamp: Time.now
    }

    puts "Retrying migration for #{table_name}."
    :retry
  end

  def abort_migration(table_name, error)
    @failed_tables << table_name
    @recovery_log << {
      table: table_name,
      action: :abort,
      error: error.class.name,
      message: error.message,
      timestamp: Time.now
    }

    puts "Migration stopped by user at table #{table_name}."
    raise MigrationError, "Migration aborted by user at table #{table_name}: #{error.message}"
  end

  def log_error(table_name, error)
    timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    puts "\n[#{timestamp}] ERROR in table #{table_name}: #{error.message}"
  end
end

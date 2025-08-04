# frozen_string_literal: true

require_relative "../configuration/configuration"
require_relative "../database/database_optimizer"
require_relative "../processors/table_processor"
require_relative "../error_handling/connection_error"
require_relative "../my_connection"
require_relative "../lite_connection"
require_relative "../validators/schema_validator"
require_relative "../recovery/recovery_manager"
require_relative "../persistence/progress_tracker"

class CoreProtectMigrator
  def initialize(interactive_mode: true, progress_file: nil)
    Configuration.validate_environment
    @interactive_mode = interactive_mode
    @mysql_connection = establish_mysql_connection
    @sqlite_connection = establish_sqlite_connection
    @optimizer = DatabaseOptimizer.new(@mysql_connection)
    @schema_validator = SchemaValidator.new(@mysql_connection, @sqlite_connection)
    @recovery_manager = RecoveryManager.new(interactive_mode: @interactive_mode)
    @progress_tracker = ProgressTracker.new(progress_file)
    @processor = TableProcessor.new(
      @mysql_connection,
      @sqlite_connection,
      schema_validator: @schema_validator,
      recovery_manager: @recovery_manager
    )
  end

  def migrate
    handle_resume_if_needed
    @optimizer.prepare_for_migration

    begin
      migrate_all_tables
      finalize_successful_migration
    rescue StandardError => e
      handle_migration_failure(e)
    ensure
      cleanup_connections
    end
  end

  private

  def handle_resume_if_needed
    return unless @progress_tracker.can_resume?

    should_resume = @interactive_mode ? @progress_tracker.prompt_for_resume : true

    if should_resume
      puts "Resuming previous migration..."
      display_resume_summary
    end
  end

  def display_resume_summary
    summary = @progress_tracker.get_progress_summary
    return unless summary

    puts "\nPrevious migration summary:"
    puts "- Progress: #{summary[:percentage_complete]}%"
    puts "- Completed tables: #{summary[:completed_tables]}"
    puts "- Skipped tables: #{summary[:skipped_tables]}"
    puts "- Failed tables: #{summary[:failed_tables]}"
    puts "- Remaining tables: #{summary[:remaining_tables]}"
    puts
  end

  def establish_mysql_connection
    MyConnection.call
  rescue StandardError => e
    raise ConnectionError, "Failed to connect to MySQL: #{e.message}"
  end

  def establish_sqlite_connection
    LiteConnection.call
  rescue StandardError => e
    raise ConnectionError, "Failed to connect to SQLite: #{e.message}"
  end

  def migrate_all_tables
    all_tables = @processor.list_tables.map { |table| table["name"] }

    unless @progress_tracker.migration_in_progress?
      @progress_tracker.save_migration_start(all_tables.size)
    end

    remaining_tables = @progress_tracker.get_remaining_tables(all_tables)

    if remaining_tables.empty?
      puts "All tables have already been processed!"
      return
    end

    puts "Processing #{remaining_tables.size} remaining tables..."

    remaining_tables.each do |table_name|
      migrate_single_table(table_name)
    end
  end

  def migrate_single_table(table_name)
    total_rows = count_table_rows(table_name)
    @progress_tracker.save_table_start(table_name, total_rows)

    puts "\n" + "="*60
    puts "Processing table: #{table_name}"
    puts "Total records: #{total_rows.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "="*60

    result = process_table_with_progress_tracking(table_name)
    handle_table_result(table_name, result)
  rescue StandardError => e
    @progress_tracker.save_table_failure(table_name, e.message)
    raise e
  end

  def process_table_with_progress_tracking(table_name)
    # Create a custom progress reporter that also updates the progress tracker
    original_reporter_class = ProgressReporter

    # Monkey patch for this migration to integrate with progress tracker
    ProgressReporter.class_eval do
      alias_method :original_report_progress, :report_progress

      define_method :report_progress do |processed_rows|
        original_report_progress(processed_rows)
        # Access the migrator's progress tracker through the global scope
        $current_progress_tracker&.save_table_progress(@table_name, processed_rows)
      end
    end

    # Set global reference for progress tracking integration
    $current_progress_tracker = @progress_tracker

    begin
      @processor.process_table(table_name)
    ensure
      # Clean up global reference
      $current_progress_tracker = nil

      # Restore original method
      ProgressReporter.class_eval do
        alias_method :report_progress, :original_report_progress
        remove_method :original_report_progress
      end
    end
  end

  def handle_table_result(table_name, result)
    case result
    when :completed
      @progress_tracker.save_table_completion(table_name, "completed")
      puts "✓ Table #{table_name} migrated successfully"
    when :completed_partial
      @progress_tracker.save_table_completion(table_name, "partial")
      puts "⚠ Table #{table_name} migrated partially (compatible columns only)"
    when :skipped
      @progress_tracker.save_table_skip(table_name, "Incompatible schema or recoverable error")
      puts "⏭ Table #{table_name} was skipped"
    else
      @progress_tracker.save_table_completion(table_name, "unknown")
      puts "? Unknown status for table #{table_name}: #{result}"
    end
  end

  def count_table_rows(table_name)
    @sqlite_connection.execute("SELECT COUNT(*) FROM #{table_name}")[0][0]
  rescue SQLite3::Exception
    0
  end

  def finalize_successful_migration
    @optimizer.finalize_migration
    @progress_tracker.save_migration_completion

    display_migration_summary
    cleanup_progress_file
  end

  def display_migration_summary
    summary = @recovery_manager.recovery_summary

    puts "\n" + "="*60
    puts "MIGRATION COMPLETED SUCCESSFULLY!"
    puts "="*60

    if summary[:skipped_tables].any?
      puts "Skipped tables: #{summary[:skipped_tables].join(', ')}"
    end

    if summary[:failed_tables].any?
      puts "Failed tables: #{summary[:failed_tables].join(', ')}"
    end

    if summary[:total_issues] > 0
      puts "Total resolved issues: #{summary[:total_issues]}"
    end

    puts "\nPlease verify the migrated data in MySQL before removing the SQLite database."
    puts "="*60
  end

  def handle_migration_failure(error)
    @progress_tracker.save_migration_failure(error.message)

    puts "\n" + "="*60
    puts "MIGRATION FAILED!"
    puts "="*60
    puts "Error: #{error.message}"

    if @recovery_manager.has_skipped_tables? || @recovery_manager.has_failed_tables?
      display_partial_results
    end

    puts "\nProgress has been saved. Run again to continue from where it left off."
    puts "="*60

    puts error.backtrace.join("\n") if ENV["DEBUG"] == "true"
    exit 1
  end

  def display_partial_results
    summary = @recovery_manager.recovery_summary

    puts "\nPartial results:"
    puts "- Skipped tables: #{summary[:skipped_tables].size}" if summary[:skipped_tables].any?
    puts "- Failed tables: #{summary[:failed_tables].size}" if summary[:failed_tables].any?
    puts "- Issues handled: #{summary[:total_issues]}"
  end

  def cleanup_progress_file
    # Only clean up if migration was fully successful
    summary = @recovery_manager.recovery_summary
    return if summary[:failed_tables].any?

    puts "Cleaning up progress file..."
    @progress_tracker.clear_progress
  end

  def cleanup_connections
    @mysql_connection&.close
    @sqlite_connection&.close
  end
end

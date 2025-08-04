# frozen_string_literal: true

require "json"
require "fileutils"

class ProgressTracker
  DEFAULT_PROGRESS_FILE = ".migration_progress.json"

  def initialize(progress_file = nil)
    @progress_file = progress_file || DEFAULT_PROGRESS_FILE
    @progress_data = load_progress || initialize_progress_data
  end

  def save_migration_start(total_tables)
    @progress_data.merge!(
      status: "in_progress",
      started_at: Time.now.to_f,
      total_tables: total_tables,
      completed_tables: [],
      skipped_tables: [],
      failed_tables: [],
      current_table: nil,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def save_table_start(table_name, total_rows)
    @progress_data.merge!(
      current_table: table_name,
      current_table_total_rows: total_rows,
      current_table_processed_rows: 0,
      current_table_started_at: Time.now.to_f,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def save_table_progress(table_name, processed_rows)
    @progress_data.merge!(
      current_table_processed_rows: processed_rows,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def save_table_completion(table_name, status = "completed")
    @progress_data[:completed_tables] << {
      name: table_name,
      status: status,
      completed_at: Time.now.to_f,
      duration: calculate_table_duration
    }

    @progress_data.merge!(
      current_table: nil,
      current_table_total_rows: 0,
      current_table_processed_rows: 0,
      current_table_started_at: nil,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def save_table_skip(table_name, reason)
    @progress_data[:skipped_tables] << {
      name: table_name,
      reason: reason,
      skipped_at: Time.now.to_f
    }

    @progress_data.merge!(
      current_table: nil,
      current_table_total_rows: 0,
      current_table_processed_rows: 0,
      current_table_started_at: nil,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def save_table_failure(table_name, error_message)
    @progress_data[:failed_tables] << {
      name: table_name,
      error: error_message,
      failed_at: Time.now.to_f
    }

    @progress_data.merge!(
      current_table: nil,
      current_table_total_rows: 0,
      current_table_processed_rows: 0,
      current_table_started_at: nil,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def save_migration_completion
    @progress_data.merge!(
      status: "completed",
      completed_at: Time.now.to_f,
      total_duration: calculate_total_duration,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def save_migration_failure(error_message)
    @progress_data.merge!(
      status: "failed",
      failed_at: Time.now.to_f,
      error: error_message,
      total_duration: calculate_total_duration,
      last_updated: Time.now.to_f
    )

    save_progress
  end

  def migration_in_progress?
    @progress_data[:status] == "in_progress"
  end

  def can_resume?
    migration_in_progress? && !@progress_data[:completed_tables].nil?
  end

  def get_completed_tables
    (@progress_data[:completed_tables] || []).map { |table| table[:name] }
  end

  def get_skipped_tables
    (@progress_data[:skipped_tables] || []).map { |table| table[:name] }
  end

  def get_remaining_tables(all_tables)
    completed = get_completed_tables
    skipped = get_skipped_tables
    processed = completed + skipped

    all_tables.reject { |table| processed.include?(table) }
  end

  def get_progress_summary
    return nil unless migration_in_progress?

    total_tables = @progress_data[:total_tables] || 0
    completed_count = (@progress_data[:completed_tables] || []).size
    skipped_count = (@progress_data[:skipped_tables] || []).size
    failed_count = (@progress_data[:failed_tables] || []).size
    processed_count = completed_count + skipped_count + failed_count

    {
      total_tables: total_tables,
      completed_tables: completed_count,
      skipped_tables: skipped_count,
      failed_tables: failed_count,
      processed_tables: processed_count,
      remaining_tables: total_tables - processed_count,
      percentage_complete: total_tables > 0 ? (processed_count.to_f / total_tables * 100).round(2) : 0,
      current_table: @progress_data[:current_table],
      current_table_progress: get_current_table_progress,
      started_at: @progress_data[:started_at],
      duration: calculate_total_duration
    }
  end

  def get_current_table_progress
    return nil unless @progress_data[:current_table]

    total_rows = @progress_data[:current_table_total_rows] || 0
    processed_rows = @progress_data[:current_table_processed_rows] || 0

    {
      total_rows: total_rows,
      processed_rows: processed_rows,
      percentage: total_rows > 0 ? (processed_rows.to_f / total_rows * 100).round(2) : 0,
      started_at: @progress_data[:current_table_started_at]
    }
  end

  def clear_progress
    File.delete(@progress_file) if File.exist?(@progress_file)
    @progress_data = initialize_progress_data
  end

  def display_resume_info
    return unless can_resume?

    summary = get_progress_summary
    puts "\n" + "="*60
    puts "PREVIOUS MIGRATION DETECTED"
    puts "="*60
    puts "Progress found:"
    puts "- Tables processed: #{summary[:processed_tables]}/#{summary[:total_tables]} (#{summary[:percentage_complete]}%)"
    puts "- Completed tables: #{summary[:completed_tables]}"
    puts "- Skipped tables: #{summary[:skipped_tables]}"
    puts "- Failed tables: #{summary[:failed_tables]}"

    if summary[:current_table]
      puts "- Current table: #{summary[:current_table]} (#{summary[:current_table_progress][:percentage]}% completed)"
    end

    puts "- Started at: #{Time.at(summary[:started_at]).strftime('%Y-%m-%d %H:%M:%S')}"
    puts "- Duration: #{format_duration(summary[:duration])}"
    puts "="*60
  end

  def prompt_for_resume
    display_resume_info

    puts "\nDo you want to continue the previous migration?"
    puts "1. [yes] Continue from where it left off"
    puts "2. [no] Start new migration (previous progress will be lost)"
    print "\nChoice (1-2): "

    input = ($stdin.gets || "").chomp.strip.downcase

    case input
    when "1", "sim", "s", "y", "yes"
      puts "✓ Continuing previous migration..."
      true
    when "2", "não", "n", "no"
      puts "✓ Starting new migration..."
      clear_progress
      false
    else
      puts "Invalid option. Please try again."
      prompt_for_resume
    end
  end

  private

  def initialize_progress_data
    {
      status: "not_started",
      total_tables: 0,
      completed_tables: [],
      skipped_tables: [],
      failed_tables: [],
      current_table: nil,
      created_at: Time.now.to_f
    }
  end

  def load_progress
    return nil unless File.exist?(@progress_file)

    JSON.parse(File.read(@progress_file), symbolize_names: true)
  rescue JSON::ParserError, Errno::ENOENT
    nil
  end

  def save_progress
    FileUtils.mkdir_p(File.dirname(@progress_file)) unless File.dirname(@progress_file) == "."
    File.write(@progress_file, JSON.pretty_generate(@progress_data))
  rescue Errno::EACCES, Errno::ENOENT => e
    puts "Warning: Could not save progress: #{e.message}"
  end

  def calculate_table_duration
    started_at = @progress_data[:current_table_started_at]
    return 0 unless started_at

    Time.now.to_f - started_at
  end

  def calculate_total_duration
    started_at = @progress_data[:started_at]
    return 0 unless started_at

    Time.now.to_f - started_at
  end

  def format_duration(seconds)
    return "0s" if seconds < 1

    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    seconds = (seconds % 60).to_i

    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0
    parts << "#{seconds}s" if seconds > 0 || parts.empty?

    parts.join(" ")
  end
end

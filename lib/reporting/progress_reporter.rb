# frozen_string_literal: true

class ProgressReporter
  def initialize(table_name, total_rows)
    @table_name = table_name
    @total_rows = total_rows
    @start_time = Time.now
  end

  def report_start
    puts "Migrating #{@table_name} with #{@total_rows} records..."
  end

  def report_progress(current_row)
    percentage = (current_row.to_f / @total_rows * 100).round(2)
    elapsed_time = Time.now - @start_time
    estimated_total = elapsed_time * @total_rows / current_row
    remaining_time = estimated_total - elapsed_time

    printf "\33[2K\r#{current_row}/#{@total_rows} (#{percentage}%%) - ETA: #{format_time(remaining_time)}"
  end

  def report_completion
    total_time = Time.now - @start_time
    puts "\ndone in #{format_time(total_time)}"
    puts
  end

  private

  def format_time(seconds)
    return "0s" if seconds <= 0

    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    secs = (seconds % 60).to_i

    if hours > 0
      "#{hours}h #{minutes}m #{secs}s"
    elsif minutes > 0
      "#{minutes}m #{secs}s"
    else
      "#{secs}s"
    end
  end
end

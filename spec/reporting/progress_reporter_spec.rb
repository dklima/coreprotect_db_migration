# frozen_string_literal: true

require "rspec"
require "timecop"
require_relative "../../lib/reporting/progress_reporter"

RSpec.describe ProgressReporter, :aggregate_failures do
  let(:table_name) { "co_users" }
  let(:total_rows) { 10_000 }
  let(:start_time) { Time.new(2023, 1, 1, 12, 0, 0) }

  # Freeze time to ensure deterministic tests for time-based calculations
  before { Timecop.freeze(start_time) }
  after { Timecop.return }

  subject(:reporter) { described_class.new(table_name, total_rows) }

  describe "#initialize" do
    it "sets the table name, total rows, and start time" do
      expect(reporter.instance_variable_get(:@table_name)).to eq(table_name)
      expect(reporter.instance_variable_get(:@total_rows)).to eq(total_rows)
      expect(reporter.instance_variable_get(:@start_time)).to eq(start_time)
    end
  end

  describe "#report_start" do
    it "prints the initial migration message" do
      expected_output = "Migrating co_users with 10000 records...\n"
      expect { reporter.report_start }.to output(expected_output).to_stdout
    end
  end

  describe "#report_completion" do
    it "prints the completion message with the total elapsed time" do
      # Simulate time passing
      Timecop.freeze(start_time)
      reporter = ProgressReporter.new(table_name, total_rows)
      Timecop.freeze(start_time + 65) # 1 minute, 5 seconds

      expected_output = "\ndone in 1m 5s\n\n"
      expect { reporter.report_completion }.to output(expected_output).to_stdout
    end

    it "handles zero elapsed time" do
      expected_output = "\ndone in 0s\n\n"
      expect { reporter.report_completion }.to output(expected_output).to_stdout
    end
  end

  describe "#report_progress" do
    context "when migration is in progress" do
      it "calculates and prints the progress, percentage, and ETA" do
        # Arrange: 2500 of 10000 rows processed in 10 seconds
        Timecop.freeze(start_time)
        reporter = ProgressReporter.new(table_name, total_rows)
        Timecop.freeze(start_time + 10)
        current_row = 2500

        # Act & Assert: ETA should be 30 more seconds (40s total - 10s elapsed)
        # 2500/10000 (25.0%) - ETA: 30s
        expected_output = "\e[2K\r2500/10000 (25.0%) - ETA: 30s"
        expect { reporter.report_progress(current_row) }.to output(expected_output).to_stdout
      end
    end

    context "when progress reaches 100%" do
      it "reports 100% with an ETA of 0s" do
        Timecop.travel(start_time + 40)
        current_row = 10_000

        expected_output = "\e[2K\r10000/10000 (100.0%) - ETA: 0s"
        expect { reporter.report_progress(current_row) }.to output(expected_output).to_stdout
      end
    end

    context "with edge cases" do
      it "handles current_row exceeding total_rows without crashing" do
        Timecop.travel(start_time + 50)
        current_row = 11_000 # More rows than expected

        expected_output = "\e[2K\r11000/10000 (110.0%) - ETA: 0s"
        expect { reporter.report_progress(current_row) }.to output(expected_output).to_stdout
      end

      context "when total_rows is zero" do
        let(:total_rows) { 0 }

        it "avoids division by zero and reports progress gracefully" do
          Timecop.travel(start_time + 1)

          # Should handle division by zero gracefully
          expect { reporter.report_progress(1) }.not_to raise_error
        end
      end

      context "when current_row is zero" do
        it "raises a FloatDomainError, highlighting a critical bug" do
          # This test confirms the presence of the bug.
          # The ETA calculation `elapsed_time * @total_rows / current_row` will fail.
          Timecop.freeze(start_time)
          reporter = ProgressReporter.new(table_name, total_rows)
          Timecop.freeze(start_time + 1)
          expect { reporter.report_progress(0) }.to raise_error(FloatDomainError)
        end
      end
    end
  end

  # Testing the private method #format_time
  describe "#format_time" do
    it "formats seconds into 'Xs'" do
      expect(reporter.send(:format_time, 59)).to eq("59s")
    end

    it "formats seconds into 'Xm Ys'" do
      expect(reporter.send(:format_time, 60)).to eq("1m 0s")
      expect(reporter.send(:format_time, 125)).to eq("2m 5s")
    end

    it "formats seconds into 'Xh Ym Zs'" do
      expect(reporter.send(:format_time, 3600)).to eq("1h 0m 0s")
      expect(reporter.send(:format_time, 3725)).to eq("1h 2m 5s")
    end

    it "returns '0s' for zero seconds" do
      expect(reporter.send(:format_time, 0)).to eq("0s")
    end

    it "returns '0s' for negative seconds" do
      expect(reporter.send(:format_time, -10)).to eq("0s")
    end
  end
end

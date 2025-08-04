# frozen_string_literal: true

require "rspec"
require_relative "../../lib/processors/table_processor"
require_relative "../../lib/error_handling/migration_error"

RSpec.describe TableProcessor, :aggregate_failures do
  let(:mysql_connection) { instance_double(Mysql2::Client) }
  let(:sqlite_connection) { instance_double(SQLite3::Database) }
  let(:statement_mock) { instance_double(SQLite3::Statement) }
  let(:schema_validator) { instance_double("SchemaValidator") }
  let(:recovery_manager) { instance_double("RecoveryManager") }

  let(:processor) do
    described_class.new(
      mysql_connection,
      sqlite_connection,
      schema_validator: schema_validator,
      recovery_manager: recovery_manager
    )
  end

  before do
    allow(sqlite_connection).to receive(:results_as_hash=)
  end

  describe "#extract_columns" do
    let(:table_name) { "co_item" }

    context "when prepare returns statement with nil columns" do
      before do
        allow(sqlite_connection).to receive(:prepare).with("SELECT * FROM #{table_name} LIMIT 1")
                                .and_return(statement_mock)
        allow(statement_mock).to receive(:columns).and_return(nil)
      end

      it "raises MigrationError with descriptive message" do
        expect { processor.send(:extract_columns, table_name) }
          .to raise_error(MigrationError, /Failed to extract columns for #{table_name}: columns returned nil/)
      end

      it "handles the nil columns gracefully without undefined method error" do
        expect { processor.send(:extract_columns, table_name) }
          .to raise_error(MigrationError)
      end
    end

    context "when prepare returns statement with valid columns" do
      before do
        allow(sqlite_connection).to receive(:prepare).with("SELECT * FROM #{table_name} LIMIT 1")
                                .and_return(statement_mock)
        allow(statement_mock).to receive(:columns).and_return(%w[id user data time])
      end

      it "returns comma-separated column names with id mapped to rowid" do
        result = processor.send(:extract_columns, table_name)
        expect(result).to eq("rowid,user,data,time")
      end

      it "maps id column to rowid" do
        result = processor.send(:extract_columns, table_name)
        expect(result).to include("rowid")
        expect(result).not_to include(",id,")
        expect(result).not_to start_with("id,")
      end
    end

    context "when SQLite raises an exception" do
      before do
        allow(sqlite_connection).to receive(:prepare)
          .and_raise(SQLite3::Exception, "table does not exist")
      end

      it "raises MigrationError with SQLite error details" do
        expect { processor.send(:extract_columns, table_name) }
          .to raise_error(MigrationError, /Failed to extract columns for #{table_name}: table does not exist/)
      end
    end
  end

  describe "#process_table" do
    let(:table_name) { "co_item" }

    before do
      # Mock basic dependencies
      allow(processor).to receive(:validate_schema_if_available)
      allow(processor).to receive(:prepare_table)
      allow(processor).to receive(:extract_columns).and_return("rowid,user,data")
      allow(processor).to receive(:count_rows).and_return(100)
      allow(processor).to receive(:migrate_data)
      allow(processor).to receive(:update_rowid_if_needed)

      # Mock ProgressReporter
      progress_reporter = instance_double("ProgressReporter")
      allow(progress_reporter).to receive(:report_start)
      allow(progress_reporter).to receive(:report_completion)
      progress_reporter_class = class_double("ProgressReporter")
      allow(progress_reporter_class).to receive(:new).with(table_name, 100).and_return(progress_reporter)
      stub_const("ProgressReporter", progress_reporter_class)
    end

    context "when extract_columns fails with nil columns bug" do
      before do
        allow(processor).to receive(:extract_columns)
          .and_raise(NoMethodError, "undefined method `map' for nil:NilClass")
      end

      it "handles the error through handle_table_error" do
        expect(processor).to receive(:handle_table_error).with(table_name, anything)
        processor.process_table(table_name)
      end
    end

    context "when processing succeeds" do
      it "returns :completed" do
        result = processor.process_table(table_name)
        expect(result).to eq(:completed)
      end

      it "calls all processing steps in order" do
        expect(processor).to receive(:validate_schema_if_available).with(table_name).ordered
        expect(processor).to receive(:prepare_table).with(table_name).ordered
        expect(processor).to receive(:extract_columns).with(table_name).ordered
        expect(processor).to receive(:count_rows).with(table_name).ordered
        expect(processor).to receive(:migrate_data).ordered
        expect(processor).to receive(:update_rowid_if_needed).with(table_name).ordered

        processor.process_table(table_name)
      end
    end
  end
end

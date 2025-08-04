# frozen_string_literal: true

require "rspec"
require_relative "../../lib/validators/schema_validator"
require_relative "../../lib/error_handling/migration_error"

RSpec.describe SchemaValidator, :aggregate_failures do
  let(:mysql_connection) { instance_double(Mysql2::Client) }
  let(:sqlite_connection) { instance_double(SQLite3::Database) }
  let(:validator) { described_class.new(mysql_connection, sqlite_connection) }

  describe "#validate_table_schema" do
    let(:table_name) { "co_sign" }

    context "when schemas match perfectly" do
      before do
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id user data])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[id user data])
      end

      it "returns true for matching schemas" do
        expect(validator.validate_table_schema(table_name)).to be true
      end
    end

    context "when MySQL is missing columns from SQLite (GitHub issue scenario)" do
      before do
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id user data created_at])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[id user created_at])
      end

      it "raises SchemaMismatchError with missing columns" do
        expect { validator.validate_table_schema(table_name) }
          .to raise_error(SchemaMismatchError) do |error|
            expect(error.table_name).to eq(table_name)
            expect(error.missing_columns).to eq([ "data" ])
            expect(error.extra_columns).to be_empty
          end
      end
    end

    context "when SQLite has extra columns" do
      before do
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id user])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[id user extra_column another_extra])
      end

      it "raises SchemaMismatchError with extra columns" do
        expect { validator.validate_table_schema(table_name) }
          .to raise_error(SchemaMismatchError) do |error|
            expect(error.table_name).to eq(table_name)
            expect(error.missing_columns).to be_empty
            expect(error.extra_columns).to eq(%w[extra_column another_extra])
          end
      end
    end

    context "when both missing and extra columns exist" do
      before do
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id user data unique_to_sqlite])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[id user unique_to_mysql])
      end

      it "raises SchemaMismatchError with both types" do
        expect { validator.validate_table_schema(table_name) }
          .to raise_error(SchemaMismatchError) do |error|
            expect(error.table_name).to eq(table_name)
            expect(error.missing_columns).to eq(%w[data unique_to_sqlite])
            expect(error.extra_columns).to eq([ "unique_to_mysql" ])
          end
      end
    end
  end

  describe "#table_exists_in_mysql?" do
    let(:table_name) { "co_sign" }

    context "when table exists in MySQL" do
      before do
        allow(mysql_connection).to receive(:query)
          .with(/SELECT COUNT.*information_schema.tables.*/)
          .and_return([ { 'count' => 1 } ])
      end

      it "returns true" do
        expect(validator.table_exists_in_mysql?(table_name)).to be true
      end
    end

    context "when table does not exist in MySQL" do
      before do
        allow(mysql_connection).to receive(:query)
          .with(/SELECT COUNT.*information_schema.tables.*/)
          .and_return([ { 'count' => 0 } ])
      end

      it "returns false" do
        expect(validator.table_exists_in_mysql?(table_name)).to be false
      end
    end

    context "when MySQL query fails" do
      before do
        allow(mysql_connection).to receive(:query)
          .with(/SELECT COUNT.*information_schema.tables.*/)
          .and_raise(Mysql2::Error, "Access denied")
      end

      it "raises the MySQL error" do
        expect { validator.table_exists_in_mysql?(table_name) }
          .to raise_error(Mysql2::Error, "Access denied")
      end
    end
  end

  describe "#get_compatible_columns" do
    let(:table_name) { "co_sign" }

    before do
      allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                      .and_return(%w[id user data created_at])
      allow(validator).to receive(:extract_mysql_columns).with(table_name)
                      .and_return(%w[id user updated_at])
    end

    it "returns only columns that exist in both schemas" do
      compatible = validator.get_compatible_columns(table_name)
      expect(compatible).to eq(%w[rowid user])
    end

    it "excludes columns that don't match" do
      compatible = validator.get_compatible_columns(table_name)
      expect(compatible).not_to include("data", "created_at", "updated_at")
    end
  end

  describe "#analyze_schema_differences" do
    let(:table_name) { "co_sign" }

    before do
      allow(validator).to receive(:table_exists_in_mysql?).with(table_name).and_return(true)
    end

    context "with 50% compatibility" do
      before do
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id user data created_at])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[id user])
      end

      it "calculates correct percentage" do
        analysis = validator.analyze_schema_differences(table_name)
        expect(analysis[:compatibility_percentage]).to eq(50.0)
      end
    end

    context "with 100% compatibility" do
      before do
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id user])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[id user])
      end

      it "returns 100%" do
        analysis = validator.analyze_schema_differences(table_name)
        expect(analysis[:compatibility_percentage]).to eq(100.0)
      end
    end

    context "with 0% compatibility" do
      before do
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[sqlite_col1 sqlite_col2])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[mysql_col1 mysql_col2])
      end

      it "returns 0%" do
        analysis = validator.analyze_schema_differences(table_name)
        expect(analysis[:compatibility_percentage]).to eq(0.0)
      end
    end

    context "when table does not exist in MySQL" do
      before do
        allow(validator).to receive(:table_exists_in_mysql?).with(table_name).and_return(false)
      end

      it "returns incompatible with reason" do
        analysis = validator.analyze_schema_differences(table_name)
        expect(analysis[:compatible]).to be false
        expect(analysis[:reason]).to eq('Table does not exist in MySQL')
      end
    end
  end

  describe "real-world CoreProtect scenario" do
    context "reproducing GitHub issue: co_sign table schema mismatch" do
      let(:table_name) { "co_sign" }

      before do
        # Simulate SQLite having 'data' column but MySQL not having it
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id user action data time])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[id user action time])
      end

      it "detects the exact issue from GitHub" do
        expect { validator.validate_table_schema(table_name) }
          .to raise_error(SchemaMismatchError) do |error|
            expect(error.table_name).to eq("co_sign")
            expect(error.missing_columns).to eq([ "data" ])
            expect(error.message).to include("Missing columns in MySQL: data")
          end
      end

      it "provides compatible columns for partial migration" do
        compatible = validator.get_compatible_columns(table_name)
        expect(compatible).to eq(%w[rowid user action time])
      end

      it "calculates 80% compatibility for partial migration" do
        allow(validator).to receive(:table_exists_in_mysql?).with(table_name).and_return(true)
        analysis = validator.analyze_schema_differences(table_name)
        expect(analysis[:compatibility_percentage]).to eq(80.0) # 4 out of 5 columns compatible
      end
    end

    context "other common CoreProtect table issues" do
      it "handles co_item table with MEDIUMBLOB data column" do
        allow(validator).to receive(:extract_sqlite_columns).with("co_item")
                        .and_return(%w[id time user data])
        allow(validator).to receive(:extract_mysql_columns).with("co_item")
                        .and_return(%w[id time user data])

        expect(validator.validate_table_schema("co_item")).to be true
      end

      it "handles tables with rowid mapping issues" do
        table_name = "co_art_map"
        allow(validator).to receive(:extract_sqlite_columns).with(table_name)
                        .and_return(%w[id art])
        allow(validator).to receive(:extract_mysql_columns).with(table_name)
                        .and_return(%w[rowid art]) # Different ID column name

        expect { validator.validate_table_schema(table_name) }
          .to raise_error(SchemaMismatchError)
      end
    end
  end
end

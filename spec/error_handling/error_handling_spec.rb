# frozen_string_literal: true

require "rspec"
require_relative "../../lib/error_handling/migration_error"
require_relative "../../lib/error_handling/connection_error"
require_relative "../../lib/error_handling/table_migration_error"

RSpec.describe "Error Handling Classes", :aggregate_failures do
  describe MigrationError do
    it "is a subclass of StandardError" do
      expect(MigrationError.superclass).to eq(StandardError)
    end

    it "can be raised with a message" do
      expect { raise MigrationError, "Test error" }.to raise_error(MigrationError, "Test error")
    end

    it "can be raised without a message" do
      expect { raise MigrationError }.to raise_error(MigrationError)
    end

    it "can be caught as StandardError" do
      begin
        raise MigrationError, "Test error"
      rescue StandardError => e
        expect(e).to be_a(MigrationError)
        expect(e.message).to eq("Test error")
      end
    end
  end

  describe ConnectionError do
    it "is a subclass of MigrationError" do
      expect(ConnectionError.superclass).to eq(MigrationError)
    end

    it "is also a subclass of StandardError (through inheritance)" do
      expect(ConnectionError.ancestors).to include(StandardError)
    end

    it "can be raised with a message" do
      expect { raise ConnectionError, "Database connection failed" }.to raise_error(ConnectionError, "Database connection failed")
    end

    it "can be caught as MigrationError" do
      begin
        raise ConnectionError, "Connection timeout"
      rescue MigrationError => e
        expect(e).to be_a(ConnectionError)
        expect(e.message).to eq("Connection timeout")
      end
    end

    it "can be caught as StandardError" do
      begin
        raise ConnectionError, "Network error"
      rescue StandardError => e
        expect(e).to be_a(ConnectionError)
        expect(e.message).to eq("Network error")
      end
    end
  end

  describe TableMigrationError do
    it "is a subclass of MigrationError" do
      expect(TableMigrationError.superclass).to eq(MigrationError)
    end

    it "is also a subclass of StandardError (through inheritance)" do
      expect(TableMigrationError.ancestors).to include(StandardError)
    end

    it "can be raised with a message" do
      expect { raise TableMigrationError, "Table migration failed" }.to raise_error(TableMigrationError, "Table migration failed")
    end

    it "can be caught as MigrationError" do
      begin
        raise TableMigrationError, "Data corruption detected"
      rescue MigrationError => e
        expect(e).to be_a(TableMigrationError)
        expect(e.message).to eq("Data corruption detected")
      end
    end

    it "can be caught as StandardError" do
      begin
        raise TableMigrationError, "SQL syntax error"
      rescue StandardError => e
        expect(e).to be_a(TableMigrationError)
        expect(e.message).to eq("SQL syntax error")
      end
    end
  end

  describe "Error Hierarchy" do
    it "maintains proper inheritance chain" do
      ancestors = TableMigrationError.ancestors
      expect(ancestors[0]).to eq(TableMigrationError)
      expect(ancestors[1]).to eq(MigrationError)
      expect(ancestors[2]).to eq(StandardError)
      expect(ancestors[3]).to eq(Exception)
      expect(ancestors).to include(Object, Kernel, BasicObject)
    end

    it "allows specific error handling" do
      errors_caught = []

      begin
        raise TableMigrationError, "Specific table error"
      rescue TableMigrationError => e
        errors_caught << [ :table_migration_error, e.message ]
      rescue ConnectionError => e
        errors_caught << [ :connection_error, e.message ]
      rescue MigrationError => e
        errors_caught << [ :migration_error, e.message ]
      end

      expect(errors_caught).to eq([ [ :table_migration_error, "Specific table error" ] ])
    end

    it "allows generic error handling" do
      errors_caught = []

      begin
        raise ConnectionError, "Generic connection error"
      rescue MigrationError => e
        errors_caught << [ :migration_error, e.class.name, e.message ]
      end

      expect(errors_caught).to eq([ [ :migration_error, "ConnectionError", "Generic connection error" ] ])
    end
  end

  describe "Real-world error scenarios" do
    it "handles MySQL connection failures" do
      error_message = "Failed to connect to MySQL: Access denied for user 'root'@'localhost'"

      expect {
        raise ConnectionError, error_message
      }.to raise_error(ConnectionError, error_message)
    end

    it "handles SQLite file not found" do
      error_message = "Failed to connect to SQLite: no such file or directory"

      expect {
        raise ConnectionError, error_message
      }.to raise_error(ConnectionError, error_message)
    end

    it "handles table migration data corruption" do
      error_message = "Failed to migrate table co_block: Data truncation: Incorrect string value"

      expect {
        raise TableMigrationError, error_message
      }.to raise_error(TableMigrationError, error_message)
    end

    it "handles generic migration failures" do
      error_message = "Migration process interrupted by user"

      expect {
        raise MigrationError, error_message
      }.to raise_error(MigrationError, error_message)
    end
  end
end

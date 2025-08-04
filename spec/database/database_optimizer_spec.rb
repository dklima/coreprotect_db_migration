# frozen_string_literal: true

require "rspec"
require_relative "../../lib/database/database_optimizer"
require_relative "../../lib/configuration/configuration"

RSpec.describe DatabaseOptimizer, :aggregate_failures do
  let(:mysql_connection) { instance_double(Mysql2::Client) }
  let(:optimizer) { described_class.new(mysql_connection) }

  before do
    # Mock Configuration responses
    allow(Configuration).to receive(:mysql_database).and_return('test_database')
    allow(mysql_connection).to receive(:query)
  end

  describe "#initialize" do
    it "stores the MySQL connection" do
      expect(optimizer.instance_variable_get(:@mysql_connection)).to eq(mysql_connection)
    end
  end

  describe "#prepare_for_migration" do
    it "optimizes database encoding and disables constraints" do
      optimizer.prepare_for_migration

      expect(mysql_connection).to have_received(:query).with(
        "ALTER DATABASE test_database CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;"
      )
      expect(mysql_connection).to have_received(:query).with('SET FOREIGN_KEY_CHECKS=0;')
      expect(mysql_connection).to have_received(:query).with('SET UNIQUE_CHECKS=0;')
      expect(mysql_connection).to have_received(:query).with('SET autocommit=0')
    end

    context "when database encoding optimization fails" do
      before do
        allow(mysql_connection).to receive(:query)
          .with("ALTER DATABASE test_database CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;")
          .and_raise(Mysql2::Error, "Access denied for user")
      end

      it "raises the MySQL error" do
        expect { optimizer.prepare_for_migration }.to raise_error(Mysql2::Error, "Access denied for user")
      end
    end

    context "when constraint disabling fails" do
      before do
        allow(mysql_connection).to receive(:query)
          .with("ALTER DATABASE test_database CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;")
        allow(mysql_connection).to receive(:query)
          .with('SET FOREIGN_KEY_CHECKS=0;')
          .and_raise(Mysql2::Error, "Variable 'foreign_key_checks' is a read only variable")
      end

      it "raises the MySQL error" do
        expect { optimizer.prepare_for_migration }.to raise_error(Mysql2::Error, "Variable 'foreign_key_checks' is a read only variable")
      end
    end
  end

  describe "#finalize_migration" do
    it "restores database settings" do
      optimizer.finalize_migration

      expect(mysql_connection).to have_received(:query).with('SET FOREIGN_KEY_CHECKS=1;')
      expect(mysql_connection).to have_received(:query).with('SET UNIQUE_CHECKS=1;')
      expect(mysql_connection).to have_received(:query).with('SET autocommit=1')
    end

    context "when constraint restoration fails" do
      before do
        allow(mysql_connection).to receive(:query)
          .with('SET FOREIGN_KEY_CHECKS=1;')
          .and_raise(Mysql2::Error, "MySQL server has gone away")
      end

      it "raises the MySQL error" do
        expect { optimizer.finalize_migration }.to raise_error(Mysql2::Error, "MySQL server has gone away")
      end
    end
  end

  describe "private methods" do
    describe "#optimize_database_encoding" do
      it "sets UTF8MB4 character set for the database" do
        optimizer.send(:optimize_database_encoding)

        expect(mysql_connection).to have_received(:query).with(
          "ALTER DATABASE test_database CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;"
        )
      end

      context "with different database names" do
        before { allow(Configuration).to receive(:mysql_database).and_return('production_minecraft') }

        it "uses the correct database name from configuration" do
          optimizer.send(:optimize_database_encoding)

          expect(mysql_connection).to have_received(:query).with(
            "ALTER DATABASE production_minecraft CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;"
          )
        end
      end

      context "with database name containing special characters" do
        before { allow(Configuration).to receive(:mysql_database).and_return('test-db_2023') }

        it "handles database names with special characters" do
          optimizer.send(:optimize_database_encoding)

          expect(mysql_connection).to have_received(:query).with(
            "ALTER DATABASE test-db_2023 CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;"
          )
        end
      end
    end

    describe "#disable_constraints_and_checks" do
      it "disables all performance and integrity checks" do
        optimizer.send(:disable_constraints_and_checks)

        expect(mysql_connection).to have_received(:query).with('SET FOREIGN_KEY_CHECKS=0;')
        expect(mysql_connection).to have_received(:query).with('SET UNIQUE_CHECKS=0;')
        expect(mysql_connection).to have_received(:query).with('SET autocommit=0')
      end
    end

    describe "#enable_constraints_and_checks" do
      it "re-enables all performance and integrity checks" do
        optimizer.send(:enable_constraints_and_checks)

        expect(mysql_connection).to have_received(:query).with('SET FOREIGN_KEY_CHECKS=1;')
        expect(mysql_connection).to have_received(:query).with('SET UNIQUE_CHECKS=1;')
        expect(mysql_connection).to have_received(:query).with('SET autocommit=1')
      end
    end
  end

  describe "integration scenarios" do
    it "can successfully run prepare and finalize in sequence" do
      expect {
        optimizer.prepare_for_migration
        optimizer.finalize_migration
      }.not_to raise_error

      # Verify all expected queries were called
      expect(mysql_connection).to have_received(:query).exactly(7).times
    end

    context "when connection is lost during optimization" do
      before do
        allow(mysql_connection).to receive(:query)
          .with('SET UNIQUE_CHECKS=0;')
          .and_raise(Mysql2::Error, "MySQL server has gone away")
      end

      it "fails gracefully with descriptive error" do
        expect { optimizer.prepare_for_migration }.to raise_error(Mysql2::Error, "MySQL server has gone away")
      end
    end
  end
end

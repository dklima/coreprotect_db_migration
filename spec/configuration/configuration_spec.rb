# frozen_string_literal: true

require "rspec"
require_relative "../../lib/configuration/configuration"

RSpec.describe Configuration, :aggregate_failures do
  describe ".validate_environment" do
    context "when .env file exists" do
      before { allow(File).to receive(:exist?).with('.env').and_return(true) }

      it "does not exit or raise errors" do
        expect { Configuration.validate_environment }.not_to raise_error
      end
    end

    context "when .env file does not exist" do
      before do
        allow(File).to receive(:exist?).with('.env').and_return(false)
        allow(Kernel).to receive(:warn)
        allow(Kernel).to receive(:exit)
      end

      it "warns user and exits with code 1" do
        Configuration.validate_environment

        expect(Kernel).to have_received(:warn).with('.env file not found.')
        expect(Kernel).to have_received(:warn).with('Please create it based on _env file and source it with "source .env" command.')
        expect(Kernel).to have_received(:warn).with('For more details, check README.md file.')
        expect(Kernel).to have_received(:exit).with(1)
      end
    end
  end

  describe ".batch_size" do
    context "when OFFSET environment variable is set" do
      before { allow(ENV).to receive(:fetch).with('OFFSET', '10000').and_return('5000') }

      it "returns OFFSET as integer" do
        expect(Configuration.batch_size).to eq(5000)
      end

      it "memoizes the result" do
        Configuration.batch_size
        Configuration.batch_size
        expect(ENV).to have_received(:fetch).once
      end
    end

    context "when OFFSET environment variable is not set" do
      before { allow(ENV).to receive(:fetch).with('OFFSET', '10000').and_return('10000') }

      it "returns default value 10000" do
        expect(Configuration.batch_size).to eq(10000)
      end
    end

    context "when OFFSET is set to invalid value" do
      before { allow(ENV).to receive(:fetch).with('OFFSET', '10000').and_return('invalid') }

      it "returns 0 due to to_i conversion" do
        expect(Configuration.batch_size).to eq(0)
      end
    end

    context "when OFFSET is set to negative value" do
      before { allow(ENV).to receive(:fetch).with('OFFSET', '10000').and_return('-100') }

      it "returns negative value" do
        expect(Configuration.batch_size).to eq(-100)
      end
    end
  end

  describe ".mysql_database" do
    context "when MYSQL_DATABASE environment variable is set" do
      before { allow(ENV).to receive(:fetch).with('MYSQL_DATABASE').and_return('test_database') }

      it "returns the database name" do
        expect(Configuration.mysql_database).to eq('test_database')
      end

      it "memoizes the result" do
        Configuration.mysql_database
        Configuration.mysql_database
        expect(ENV).to have_received(:fetch).once
      end
    end

    context "when MYSQL_DATABASE environment variable is missing" do
      before { allow(ENV).to receive(:fetch).with('MYSQL_DATABASE').and_raise(KeyError, 'key not found: "MYSQL_DATABASE"') }

      it "raises KeyError" do
        expect { Configuration.mysql_database }.to raise_error(KeyError, 'key not found: "MYSQL_DATABASE"')
      end
    end

    context "when MYSQL_DATABASE is empty string" do
      before { allow(ENV).to receive(:fetch).with('MYSQL_DATABASE').and_return('') }

      it "returns empty string" do
        expect(Configuration.mysql_database).to eq('')
      end
    end
  end

  describe "REQUIRED_ENV_VARS constant" do
    it "contains all required environment variables" do
      expected_vars = %w[
        MYSQL_HOST MYSQL_USER MYSQL_PASS MYSQL_PORT MYSQL_DATABASE
        SQLITE_DATABASE OFFSET
      ]
      expect(Configuration::REQUIRED_ENV_VARS).to eq(expected_vars)
    end

    it "is frozen to prevent modification" do
      expect(Configuration::REQUIRED_ENV_VARS).to be_frozen
    end
  end

  # Test class variable cleanup between tests
  describe "memoization reset" do
    before do
      allow(ENV).to receive(:fetch).with('OFFSET', '10000').and_return('1000')
      allow(ENV).to receive(:fetch).with('MYSQL_DATABASE').and_return('first_db')
    end

    it "can be reset by clearing instance variables" do
      # First call
      expect(Configuration.batch_size).to eq(1000)
      expect(Configuration.mysql_database).to eq('first_db')

      # Change environment and clear memoization
      Configuration.instance_variable_set(:@batch_size, nil)
      Configuration.instance_variable_set(:@mysql_database, nil)

      allow(ENV).to receive(:fetch).with('OFFSET', '10000').and_return('2000')
      allow(ENV).to receive(:fetch).with('MYSQL_DATABASE').and_return('second_db')

      # Second call should use new values
      expect(Configuration.batch_size).to eq(2000)
      expect(Configuration.mysql_database).to eq('second_db')
    end
  end
end

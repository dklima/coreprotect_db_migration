# frozen_string_literal: true

require "rspec"
require "timecop"

RSpec.configure do |config|
  # Use only the new `expect` syntax to avoid confusions
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Use colored output
  config.color = true

  # Use documentation format for better readability
  config.default_formatter = "doc" if config.files_to_run.one?

  # Clean up memoized values between tests
  config.before(:each) do
    # Reset Configuration class variables to ensure clean state
    Configuration.instance_variable_set(:@batch_size, nil) if defined?(Configuration)
    Configuration.instance_variable_set(:@mysql_database, nil) if defined?(Configuration)
  end

  # Clean up Timecop after each test that uses it
  config.after(:each) do
    Timecop.return if defined?(Timecop)
  end

  # Filter out stack trace lines for cleaner output
  config.filter_gems_from_backtrace "rspec-core", "rspec-expectations", "rspec-mocks"

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option.
  Kernel.srand config.seed

  # Allow focusing on specific tests with :focus tag
  config.filter_run_when_matching :focus

  # Configure warnings
  config.warnings = false

  # Share examples for common behavior
  config.shared_context_metadata_behavior = :apply_to_host_groups
end

# Load all required dependencies
require_relative "../lib/configuration/configuration"
require_relative "../lib/error_handling/migration_error"
require_relative "../lib/error_handling/connection_error"
require_relative "../lib/error_handling/table_migration_error"
require_relative "../lib/reporting/progress_reporter"
require_relative "../lib/database/database_optimizer"
require_relative "../lib/formatters/value_formatter"
require_relative "../lib/processors/table_processor"
require_relative "../lib/migrators/core_protect_migrator"
require_relative "../lib/validators/schema_validator"
require_relative "../lib/recovery/recovery_manager"
require_relative "../lib/persistence/progress_tracker"
require_relative "../lib/my_connection"
require_relative "../lib/lite_connection"

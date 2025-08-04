# frozen_string_literal: true

# Load all necessary dependencies
require_relative 'lib/error_handling/migration_error'
require_relative 'lib/error_handling/connection_error'
require_relative 'lib/error_handling/table_migration_error'
require_relative 'lib/configuration/configuration'
require_relative 'lib/reporting/progress_reporter'
require_relative 'lib/database/database_optimizer'
require_relative 'lib/formatters/value_formatter'
require_relative 'lib/processors/table_processor'
require_relative 'lib/migrators/core_protect_migrator'

# Execute migration if script is run directly
if __FILE__ == $PROGRAM_NAME
  # Parse command line options
  interactive_mode = !ARGV.include?('--non-interactive')
  progress_file = ARGV.find { |arg| arg.start_with?('--progress-file=') }&.split('=', 2)&.last

  puts "="*60
  puts "COREPROTECT DATABASE MIGRATION"
  puts "Sistema aprimorado com recovery e validação de schema"
  puts "="*60
  puts

  if interactive_mode
    puts "Modo interativo ativado - você será consultado sobre problemas encontrados"
  else
    puts "Modo não-interativo - problemas serão tratados automaticamente"
  end

  puts "Arquivo de progresso: #{progress_file || 'padrão (.migration_progress.json)'}"
  puts

  migrator = CoreProtectMigrator.new(
    interactive_mode: interactive_mode,
    progress_file: progress_file
  )

  migrator.migrate
end

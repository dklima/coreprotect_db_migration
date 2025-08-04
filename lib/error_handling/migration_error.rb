# frozen_string_literal: true

class MigrationError < StandardError; end

class SchemaMismatchError < MigrationError
  attr_reader :table_name, :missing_columns, :extra_columns

  def initialize(table_name, missing_columns = [], extra_columns = [])
    @table_name = table_name
    @missing_columns = missing_columns
    @extra_columns = extra_columns

    message = build_error_message
    super(message)
  end

  private

  def build_error_message
    parts = [ "Schema mismatch in table '#{@table_name}'" ]

    unless @missing_columns.empty?
      parts << "Missing columns in MySQL: #{@missing_columns.join(', ')}"
    end

    unless @extra_columns.empty?
      parts << "Extra columns in SQLite: #{@extra_columns.join(', ')}"
    end

    parts.join(". ")
  end
end

class RecoverableError < MigrationError
  attr_reader :table_name, :recovery_actions

  def initialize(table_name, message, recovery_actions = [])
    @table_name = table_name
    @recovery_actions = recovery_actions
    super("#{message} (Table: #{table_name})")
  end
end

# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/recovery/recovery_manager'
require_relative '../../lib/error_handling/migration_error'

RSpec.describe RecoveryManager do
  let(:recovery_manager) { RecoveryManager.new(interactive_mode: false) }
  let(:table_name) { 'co_user' }
  let(:error) { MigrationError.new('Test error') }

  describe '#initialize' do
    it 'initializes with default values', :aggregate_failures do
      manager = RecoveryManager.new

      expect(manager.has_skipped_tables?).to be false
      expect(manager.has_failed_tables?).to be false
    end
  end

  describe '#handle_table_error' do
    context 'in non-interactive mode' do
      context 'with SchemaMismatchError' do
        let(:schema_error) { SchemaMismatchError.new(table_name, [ 'data' ], []) }

        it 'automatically skips the table', :aggregate_failures do
          allow(recovery_manager).to receive(:puts)

          result = recovery_manager.handle_table_error(table_name, schema_error)

          expect(result).to eq(:continue)
          expect(recovery_manager.has_skipped_tables?).to be true
        end
      end

      context 'with other errors' do
        it 'aborts the migration', :aggregate_failures do
          allow(recovery_manager).to receive(:puts)

          expect { recovery_manager.handle_table_error(table_name, error) }.to raise_error(MigrationError)
          expect(recovery_manager.has_failed_tables?).to be true
        end
      end
    end
  end

  describe '#handle_schema_mismatch' do
    let(:schema_error) { SchemaMismatchError.new(table_name, [ 'data' ], [ 'extra' ]) }

    context 'in non-interactive mode' do
      context 'when only extra columns exist' do
        let(:schema_error_extra_only) { SchemaMismatchError.new(table_name, [], [ 'extra' ]) }

        it 'attempts to migrate compatible columns', :aggregate_failures do
          allow(recovery_manager).to receive(:puts)

          result = recovery_manager.handle_schema_mismatch(table_name, schema_error_extra_only)

          expect(result).to eq(:skip_columns)
        end
      end

      context 'when missing columns exist' do
        it 'skips the table', :aggregate_failures do
          allow(recovery_manager).to receive(:puts)

          result = recovery_manager.handle_schema_mismatch(table_name, schema_error)

          expect(result).to eq(:continue)
          expect(recovery_manager.has_skipped_tables?).to be true
        end
      end
    end
  end

  describe '#recovery_summary' do
    before do
      allow(recovery_manager).to receive(:puts)
      recovery_manager.handle_table_error('table1', SchemaMismatchError.new('table1', [ 'col1' ], []))
      recovery_manager.handle_table_error('table2', error)
    rescue MigrationError
      # Expected for the second error
    end

    it 'provides comprehensive recovery statistics', :aggregate_failures do
      summary = recovery_manager.recovery_summary

      expect(summary[:skipped_tables]).to include('table1')
      expect(summary[:failed_tables]).to include('table2')
      expect(summary[:total_issues]).to eq(2)
      expect(summary[:recovery_log]).not_to be_empty
    end
  end

  describe 'logging functionality' do
    it 'logs errors with timestamps', :aggregate_failures do
      allow(recovery_manager).to receive(:puts)

      recovery_manager.handle_table_error(table_name, SchemaMismatchError.new(table_name, [ 'data' ], []))
      summary = recovery_manager.recovery_summary

      log_entry = summary[:recovery_log].first
      expect(log_entry[:table]).to eq(table_name)
      expect(log_entry[:action]).to eq(:skip)
      expect(log_entry[:error]).to eq('SchemaMismatchError')
      expect(log_entry[:timestamp]).to be_a(Time)
    end
  end
end

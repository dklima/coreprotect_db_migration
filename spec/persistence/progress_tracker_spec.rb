# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../lib/persistence/progress_tracker'

RSpec.describe ProgressTracker do
  let(:temp_file) { Tempfile.new('test_progress') }
  let(:progress_tracker) { ProgressTracker.new(temp_file.path) }

  after do
    temp_file.unlink
  end

  describe '#initialize' do
    it 'creates new progress data when no file exists' do
      non_existent_file = ProgressTracker.new('/tmp/non_existent_progress.json')

      expect(non_existent_file.migration_in_progress?).to be false
    end

    it 'loads existing progress data when file exists', :aggregate_failures do
      progress_tracker.save_migration_start(5)

      loaded_tracker = ProgressTracker.new(temp_file.path)

      expect(loaded_tracker.migration_in_progress?).to be true
      expect(loaded_tracker.can_resume?).to be true
    end
  end

  describe 'migration lifecycle' do
    it 'tracks complete migration lifecycle', :aggregate_failures do
      # Start migration
      progress_tracker.save_migration_start(3)
      expect(progress_tracker.migration_in_progress?).to be true

      # Process first table
      progress_tracker.save_table_start('table1', 1000)
      progress_tracker.save_table_progress('table1', 500)
      progress_tracker.save_table_completion('table1', 'completed')

      # Skip second table
      progress_tracker.save_table_skip('table2', 'Schema mismatch')

      # Fail third table
      progress_tracker.save_table_failure('table3', 'Connection error')

      # Verify state before completion
      expect(progress_tracker.get_completed_tables).to include('table1')
      expect(progress_tracker.get_skipped_tables).to include('table2')

      summary = progress_tracker.get_progress_summary
      expect(summary[:completed_tables]).to eq(1)
      expect(summary[:skipped_tables]).to eq(1)
      expect(summary[:failed_tables]).to eq(1)

      # Complete migration
      progress_tracker.save_migration_completion
    end
  end

  describe '#get_remaining_tables' do
    before do
      progress_tracker.save_migration_start(4)
      progress_tracker.save_table_completion('table1', 'completed')
      progress_tracker.save_table_skip('table2', 'Schema mismatch')
    end

    it 'returns only unprocessed tables', :aggregate_failures do
      all_tables = [ 'table1', 'table2', 'table3', 'table4' ]
      remaining = progress_tracker.get_remaining_tables(all_tables)

      expect(remaining).to include('table3', 'table4')
      expect(remaining).not_to include('table1', 'table2')
      expect(remaining.size).to eq(2)
    end
  end

  describe '#get_progress_summary' do
    before do
      progress_tracker.save_migration_start(5)
      progress_tracker.save_table_completion('table1', 'completed')
      progress_tracker.save_table_skip('table2', 'Schema mismatch')
    end

    it 'provides comprehensive progress information', :aggregate_failures do
      summary = progress_tracker.get_progress_summary

      expect(summary[:total_tables]).to eq(5)
      expect(summary[:completed_tables]).to eq(1)
      expect(summary[:skipped_tables]).to eq(1)
      expect(summary[:failed_tables]).to eq(0)
      expect(summary[:processed_tables]).to eq(2)
      expect(summary[:remaining_tables]).to eq(3)
      expect(summary[:percentage_complete]).to eq(40.0)
      expect(summary[:started_at]).to be_a(Float)
      expect(summary[:duration]).to be >= 0
    end
  end

  describe '#get_current_table_progress' do
    context 'when no current table is being processed' do
      it 'returns nil' do
        expect(progress_tracker.get_current_table_progress).to be_nil
      end
    end

    context 'when a table is being processed' do
      before do
        progress_tracker.save_migration_start(3)
        progress_tracker.save_table_start('current_table', 2000)
        progress_tracker.save_table_progress('current_table', 800)
      end

      it 'provides current table progress details', :aggregate_failures do
        progress = progress_tracker.get_current_table_progress

        expect(progress[:total_rows]).to eq(2000)
        expect(progress[:processed_rows]).to eq(800)
        expect(progress[:percentage]).to eq(40.0)
        expect(progress[:started_at]).to be_a(Float)
      end
    end
  end

  describe '#clear_progress' do
    before do
      progress_tracker.save_migration_start(3)
      progress_tracker.save_table_completion('table1', 'completed')
    end

    it 'removes progress file and resets state', :aggregate_failures do
      expect(File.exist?(temp_file.path)).to be true

      progress_tracker.clear_progress

      expect(File.exist?(temp_file.path)).to be false
      expect(progress_tracker.migration_in_progress?).to be false
      expect(progress_tracker.can_resume?).to be false
    end
  end

  describe 'error handling' do
    it 'handles file access errors gracefully' do
      # Create tracker with invalid path
      invalid_tracker = ProgressTracker.new('/invalid/path/progress.json')

      # Should not raise error when trying to save
      expect { invalid_tracker.save_migration_start(3) }.not_to raise_error
    end
  end
end

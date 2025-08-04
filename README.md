# CoreProtect SQLite to MySQL Migration Tool

[![Ruby](https://img.shields.io/badge/Ruby-3.0%2B-red.svg)](https://www.ruby-lang.org/)
[![RSpec](https://img.shields.io/badge/Tested%20with-RSpec-green.svg)](https://rspec.info/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A robust and well-tested migration tool specifically designed to migrate CoreProtect data from SQLite to MySQL/MariaDB/Percona. While built for CoreProtect, this tool can be adapted for any SQLite to MySQL migration with minimal modifications.

## ⚠️ Important Disclaimer

**This tool performs destructive operations including `TRUNCATE` statements on MySQL tables.**

- Always backup your databases before running
- Test on non-production data first  
- Understand what the tool does before executing
- Use at your own risk

## 🚀 Quick Start

1. **Configure the environment:**
   ```bash
   cp _env .env
   # Edit .env with your database credentials
   ```

2. **Load environment variables:**
   ```bash
   source .env
   ```

3. **Install dependencies:**
   ```bash
   bundle install
   ```

4. **Run the migration:**
   ```bash
   ruby ./migration.rb
   ```

## 📋 Prerequisites

### Database Requirements

**MySQL/MariaDB/Percona:**
- Target database must exist
- CoreProtect tables must be pre-created with identical structure to SQLite
- Sufficient privileges for INSERT, TRUNCATE, and ALTER operations

**SQLite:**
- Source database file (`database.db`) must be accessible
- File permissions allowing read access

### Ruby Environment

- **Ruby 3.0+** (tested with Ruby 3.0)
- **Required gems:**
  - `sqlite3` - SQLite database interface
  - `mysql2` - MySQL database interface
  - `rspec` (development/testing)

### System Requirements

- Sufficient disk space for temporary operations
- Network connectivity to MySQL server
- Memory proportional to batch size (OFFSET value)

## ⚙️ Configuration

### Environment Variables

Create a `.env` file based on the provided `_env` template:

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `MYSQL_HOST` | MySQL server hostname | `localhost` | ✅ |
| `MYSQL_USER` | MySQL username | `root` | ✅ |
| `MYSQL_PASS` | MySQL password | `password123` | ✅ |
| `MYSQL_DATABASE` | Target database name | `minecraft` | ✅ |
| `MYSQL_PORT` | MySQL port number | `3306` | ✅ |
| `OFFSET` | Batch size for processing | `200000` | ✅ |
| `SQLITE_DATABASE` | Path to SQLite file | `./database.db` | ✅ |

### Loading Configuration

**Linux/macOS:**
```bash
source ./.env
```

**Windows (PowerShell):**
```powershell
Get-Content .env | ForEach-Object { 
    if ($_ -match '^([^=]+)=(.*)$') { 
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2]) 
    } 
}
```

## 🔧 Advanced Configuration

### Batch Size Optimization

The `OFFSET` value controls batch processing size:

- **Small batches (10,000-50,000):** Slower but more memory efficient
- **Large batches (200,000-500,000):** Faster but requires more memory
- **Very large tables:** Consider smaller batches for stability

### MySQL Optimization

For better performance, consider these MySQL settings:

```sql
SET GLOBAL innodb_buffer_pool_size = 2G;
SET GLOBAL max_allowed_packet = 1073741824;
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
```

## 🧪 Testing

This project includes comprehensive test coverage:

```bash
# Run all tests
bundle exec rspec

# Run specific test categories
bundle exec rspec spec/processors/
bundle exec rspec spec/formatters/
bundle exec rspec spec/validators/

# Run with coverage report
bundle exec rspec --format documentation
```

**Test Coverage:**
- ✅ 122 examples, 0 failures
- ✅ Unit tests for all core components
- ✅ Integration tests for migration workflows
- ✅ Error handling and edge cases
- ✅ Schema validation and compatibility

## 📊 Migration Process

### What It Does

1. **Validation Phase:**
   - Validates environment configuration
   - Checks database connections
   - Verifies table schema compatibility

2. **Preparation Phase:**
   - Optimizes MySQL settings for bulk operations
   - Disables foreign key checks and constraints
   - Sets up progress tracking

3. **Migration Phase:**
   - Processes tables in batches (OFFSET size)
   - Handles data type conversions (Base64 for binary data)
   - Maps SQLite `id` columns to MySQL `rowid`
   - Provides real-time progress reporting

4. **Finalization Phase:**
   - Re-enables constraints and checks  
   - Restores MySQL settings
   - Generates migration summary

### Progress Tracking

The tool provides detailed progress information:
- Current table being processed
- Records migrated vs total records
- Estimated time remaining (ETA)
- Overall migration percentage

### Recovery Features

- **Automatic Resume:** Continue from last successful batch
- **Schema Mismatch Handling:** Skip incompatible tables or migrate partial data
- **Error Recovery:** Graceful handling of connection issues and data errors

## 🛠️ Troubleshooting

### Common Issues

**1. `Packets larger than max_allowed_packet are not allowed`**

*Solution:* Increase MySQL packet size or reduce batch size:
```sql
SET GLOBAL max_allowed_packet=1073741824;
```
*Or* reduce `OFFSET` in `.env` file.

**2. `undefined method 'map' for nil`**

*Status:* ✅ **Fixed** - This critical bug has been resolved in the current version.

**3. Memory Issues with Large Tables**

*Solution:* Reduce the `OFFSET` value:
```bash
# In .env file
OFFSET=50000  # Reduced from 200000
```

**4. Connection Timeouts**

*Solution:* Increase MySQL timeout settings:
```sql
SET GLOBAL wait_timeout = 28800;
SET GLOBAL interactive_timeout = 28800;
```

**5. Schema Mismatch Errors**

The tool will:
- Report missing/extra columns
- Offer to migrate compatible columns only
- Allow skipping problematic tables

## 📈 Performance Expectations

### Typical Migration Times

| Table Size | Records | Estimated Time |
|------------|---------|----------------|
| Small | < 100K | 1-5 minutes |
| Medium | 100K-1M | 5-30 minutes |
| Large | 1M-10M | 30min-2 hours |
| Very Large | 10M+ | 2-8+ hours |

**Note:** `co_block` tables with 89M+ records may require 5+ hours.

### Optimization Tips

1. **Use SSD storage** for both source and target databases
2. **Increase MySQL buffer pool** size
3. **Run during low-traffic periods**
4. **Monitor system resources** during migration
5. **Consider table-specific batch sizes** for problematic tables

## 🏗️ Architecture

### Core Components

- **`TableProcessor`** - Handles individual table migration logic
- **`ValueFormatter`** - Converts SQLite data types to MySQL format
- **`SchemaValidator`** - Validates table compatibility
- **`ProgressTracker`** - Manages migration state and recovery
- **`RecoveryManager`** - Handles errors and resume functionality
- **`DatabaseOptimizer`** - Manages MySQL performance settings

### Design Principles

- **Defensive Programming:** Extensive error handling and validation
- **Testability:** Comprehensive test suite with high coverage
- **Recoverability:** Ability to resume from failures
- **Observability:** Detailed logging and progress reporting
- **Modularity:** Clean separation of concerns

## 🤝 Contributing

Contributions are welcome! Please ensure:

1. **All tests pass:** `bundle exec rspec`
2. **Follow Ruby conventions:** Use consistent style
3. **Add tests for new features:** Maintain test coverage
4. **Update documentation:** Keep README current

## 📝 License

This project is open source and available under the [MIT License](LICENSE).

## 🆘 Support

If you encounter issues:

1. **Check the troubleshooting section** above
2. **Review test results:** `bundle exec rspec`
3. **Enable debug logging** for detailed output
4. **Open an issue** with complete error details and environment info

---

**Built with ❤️ for the Minecraft community**

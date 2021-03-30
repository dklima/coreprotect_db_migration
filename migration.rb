require 'base64'
require 'json'
require_relative 'lib/my_connection'
require_relative 'lib/lite_connection'

# Exit if .env not found
unless File.exist?('.env')
  warn '.env file not found.'
  warn 'Please create it based on _env file and source it with "source .env" command.'
  warn 'For more details, check README.md file.'
  exit 1
end

def my_conn
  @my_conn ||= MyConnection.call
end

# Empty given MySQL table before migration
def my_clean_table(table)
  printf "Truncating #{table}... "
  my_conn.query("TRUNCATE TABLE `#{table}`")
  my_conn.query("ALTER TABLE `#{table}` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
  if table == 'co_item'
    my_conn.query('ALTER TABLE `co_item` CHANGE `data` `data` MEDIUMBLOB NULL;')
  end
  puts 'done'
end

def my_insert_data(params = {})
  table = params[:table]
  columns = params[:columns]
  values = params[:values]
  my_conn.query('START TRANSACTION')
  my_conn.query("INSERT INTO #{table} (#{columns}) VALUES #{values}")
  my_conn.query('COMMIT')
end

def lite_conn
  @lite_conn ||= LiteConnection.call
end

def lite_tables
  lite_conn.execute('SELECT name FROM sqlite_master WHERE type="table" ORDER BY name;')
end

def lite_count(table)
  lite_conn.execute("SELECT COUNT(*) FROM #{table}")[0][0]
end

def lite_table_columns(table)
  lite_conn.prepare("SELECT * FROM #{table} LIMIT 1").columns.map { |c| c == 'id' ? 'rowid' : c }.join(',')
end

def lite_select(params = {})
  table = params[:table]
  offset = params[:offset]
  lite_conn.execute("SELECT * FROM #{table} LIMIT #{ENV.fetch('OFFSET').to_s} OFFSET #{offset}")
end

def my_prepare_to_insert(params = {})
  values = ''

  params[:rows].each do |row|
    values << '('
    row.each do |_field, value|
      values << ", #{value.is_a?(String) ? "FROM_BASE64('#{Base64.encode64(value).strip}')" : value.to_json}"
    end
    values << '),'
  end
  my_insert_data({
    table: params[:table],
    columns: params[:columns],
    values: values.gsub('(, ', '(').gsub(/\),$/, ')')
  })
end

# Change encoding to utf8mb4 on database to support emojis
my_conn.query("ALTER DATABASE #{ENV.fetch('MYSQL_DATABASE')} CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;")

# Commands do speed up data load
my_conn.query('SET FOREIGN_KEY_CHECKS=0;')
my_conn.query('SET UNIQUE_CHECKS=0;')
my_conn.query('SET autocommit=0')

# We want sqlite results to be hashes
lite_conn.results_as_hash = true

# Lets loop over the sqlite's tables
lite_tables.each do |table|
  # First clean the table that will be filled with data
  my_clean_table(table['name'])

  # Get columns from table
  columns = lite_table_columns(table['name'])

  # Get total fields from the given table
  total_rows = lite_count(table['name'])

  printf "Migrating #{table['name']} with #{total_rows} records... "
  i = 0
  until i > total_rows
    rows = []
    lite_select({ table: table['name'], offset: i }).each do |row|
      rows << row
    end
    my_prepare_to_insert({ table: table['name'], columns: columns, rows: rows })
    i += ENV.fetch('OFFSET').to_i
  end

  puts 'done'
  puts
end

# Enable checks again
my_conn.query('SET FOREIGN_KEY_CHECKS=1;')
my_conn.query('SET UNIQUE_CHECKS=1;')
my_conn.query('SET autocommit=1')

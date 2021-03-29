# CoreProtect migration from SQLite to MySQL

## Configuration (tl;dr)

Copy `_env` file to `.env`
```
cp _env .env
```

Then, edit `.env` file to reflect your configuration.

Source it before running:
```
source .env
```

Run `bundle` to install required gems:
```
bundle
```

Run it
```
ruby ./migration.rb
```

## Pre requisites
### MySQL
- Database
- CoreProtect tables
  - Tables must have the same name from `database.db` SQLite file

### Ruby
- `sqlite3`
- `mysql2`

### Environment variables
| ENV | Value example |
| --- | ----- |
| `MYSQL_HOST` | `localhost` |
| `MYSQL_USER` | user |
| `MYSQL_PASS` | password |
| `MYSQL_DATABASE` | `minecraft` |
| `MYSQL_PORT` | 3306 |
| `SQLITE_DATABASE` | `database.db` |

There is a `_env` file you can use as template.

Copy `_env` file to `.env` and change the values as needed.

On Linux and macOS, you have to `source` it to load them to current shell session:

```
source ./.env
```

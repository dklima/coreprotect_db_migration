# CoreProtect migration from SQLite to MySQL
Even though this script was made to migrate CoreProtect data, it may be used to migrate any SQLite database to MariaDB/MySQL/Percona with little or no modifications.

## Disclaimer
Due to its nature, this script have some destructive potencial because of `TRUNCATE` statements.

Use at your own risk and know what you are doing.
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
| `OFFSET` | 200000 |
| `SQLITE_DATABASE` | `database.db` |

There is a `_env` file you can use as template.

Copy `_env` file to `.env` and change the values as needed.

On Linux and macOS, you have to `source` it to load them to current shell session:
```
    source ./.env
```

## FAQ
### I'm getting the error `Packets larger than max_allowed_packet are not allowed.`
If you are the MySQL server owner or admin and have access to alter its configurations, increase the `max_allowed_packet` parameter.

You can also try executing the statement:
```
    SET GLOBAL max_allowed_packet=1073741824;
```
However, keep in mind that it won't be persisted and will be reseted when MySQL server restarts.

If you do not have access to the MySQL configuration, you should try lowering the `OFFSET` value from `.env` file.
## Known issues
For `co_block` table with 89,000,000+ records, it may take more than 5 hours to migrate.

## Todo
Docker interactive?

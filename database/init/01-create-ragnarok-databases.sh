#!/usr/bin/env bash
set -Eeuo pipefail

# Official MariaDB image runs this only when initializing a brand-new data
# directory. Existing database volumes are intentionally left untouched.
: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set}"
: "${RAGNAROK_DB_NAME:=ragnarok}"
: "${RAGNAROK_LOG_DB_NAME:=ragnarok_logs}"
: "${RAGNAROK_DB_USER:=ragnarok}"
: "${RAGNAROK_DB_PASSWORD:?RAGNAROK_DB_PASSWORD must be set}"

for identifier in "$RAGNAROK_DB_NAME" "$RAGNAROK_LOG_DB_NAME" "$RAGNAROK_DB_USER"; do
  if [[ ! "$identifier" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "ERROR: database names and username may contain only letters, numbers, and underscores." >&2
    exit 64
  fi
done
if [[ "$RAGNAROK_DB_NAME" == "$RAGNAROK_LOG_DB_NAME" ]]; then
  echo "ERROR: main and log database names must be different." >&2
  exit 64
fi

# Escape single quotes for SQL string literals.
db_password_sql=${RAGNAROK_DB_PASSWORD//\'/\'\'}
mariadb --protocol=socket -uroot -p"$MARIADB_ROOT_PASSWORD" <<SQL
CREATE DATABASE IF NOT EXISTS \`$RAGNAROK_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`$RAGNAROK_LOG_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$RAGNAROK_DB_USER'@'%' IDENTIFIED BY '$db_password_sql';
GRANT ALL PRIVILEGES ON \`$RAGNAROK_DB_NAME\`.* TO '$RAGNAROK_DB_USER'@'%';
GRANT ALL PRIVILEGES ON \`$RAGNAROK_LOG_DB_NAME\`.* TO '$RAGNAROK_DB_USER'@'%';
FLUSH PRIVILEGES;
SQL

echo "Created or verified dedicated Ragnarok databases and grants."

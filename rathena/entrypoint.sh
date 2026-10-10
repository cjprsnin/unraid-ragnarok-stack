#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

cd /rathena
rm -f /tmp/rathena-ready

# Unraid bind mounts are commonly root-owned. Initialize and fix ownership once,
# then re-exec this script as the unprivileged rAthena account.
if [[ "$(id -u)" -eq 0 ]]; then
  mkdir -p conf save log
  if [[ ! -f conf/login_athena.conf || ! -f conf/char_athena.conf || ! -f conf/map_athena.conf ]]; then
    cp -an /usr/share/rathena-default-conf/. conf/
  fi
  chown -R rathena:rathena conf save log
  exec gosu rathena "$0" "$@"
fi

: "${DB_HOST:=ragnarok-db}"
: "${DB_PORT:=3306}"
: "${DB_NAME:=ragnarok}"
: "${LOG_DB_NAME:=ragnarok_logs}"
: "${DB_USER:=ragnarok}"
: "${DB_PASSWORD:?Set DB_PASSWORD for the dedicated Ragnarok SQL user}"
: "${SERVER_IP:?Set SERVER_IP to the server LAN address}"
: "${AUTO_IMPORT_SQL:=true}"

# Validate database identifiers before placing them into generated configuration.
for database_name in "${DB_NAME}" "${LOG_DB_NAME}"; do
  case "${database_name}" in
    ""|*[!A-Za-z0-9_]*) echo "ERROR: database names may contain only letters, numbers, and underscores." >&2; exit 64 ;;
  esac
done
if [[ "${DB_NAME}" == "${LOG_DB_NAME}" ]]; then
  echo "ERROR: DB_NAME and LOG_DB_NAME must be different databases." >&2
  exit 64
fi

# A bind-mounted empty conf directory must not erase the upstream configuration.
if [[ ! -f conf/login_athena.conf || ! -f conf/char_athena.conf || ! -f conf/map_athena.conf ]]; then
  if [[ ! -d /usr/share/rathena-default-conf ]]; then
    echo "ERROR: rAthena configuration files are missing and no defaults are available." >&2
    exit 78
  fi
  echo "Initializing persistent rAthena configuration from the image defaults."
  cp -an /usr/share/rathena-default-conf/. conf/
fi

mkdir -p conf/import save log
# Generate only our dedicated import override; do not overwrite upstream config files.
cat > conf/import/inter_conf.txt <<EOF
// Managed by the container entrypoint. Keep local customizations in separate import files.
login_server_ip: ${DB_HOST}
login_server_port: ${DB_PORT}
login_server_id: ${DB_USER}
login_server_pw: ${DB_PASSWORD}
login_server_db: ${DB_NAME}
ipban_db_ip: ${DB_HOST}
ipban_db_port: ${DB_PORT}
ipban_db_id: ${DB_USER}
ipban_db_pw: ${DB_PASSWORD}
ipban_db_db: ${DB_NAME}
char_server_ip: ${DB_HOST}
char_server_port: ${DB_PORT}
char_server_id: ${DB_USER}
char_server_pw: ${DB_PASSWORD}
char_server_db: ${DB_NAME}
map_server_ip: ${DB_HOST}
map_server_port: ${DB_PORT}
map_server_id: ${DB_USER}
map_server_pw: ${DB_PASSWORD}
map_server_db: ${DB_NAME}
log_db_ip: ${DB_HOST}
log_db_port: ${DB_PORT}
log_db_id: ${DB_USER}
log_db_pw: ${DB_PASSWORD}
log_db_db: ${LOG_DB_NAME}
EOF

# Advertise the LAN/public address to game clients. Internal server-to-server
# communication continues to use the upstream loopback defaults.
cat > conf/import/char_conf.txt <<EOF
// Managed by the container entrypoint.
char_ip: ${SERVER_IP}
EOF

cat > conf/import/map_conf.txt <<EOF
// Managed by the container entrypoint.
map_ip: ${SERVER_IP}
EOF

# Wait for the existing MariaDB service; do not create or modify databases.
echo "Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
db_ready=false
for attempt in $(seq 1 60); do
  if MYSQL_PWD="${DB_PASSWORD}" mariadb-admin --silent -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" ping >/dev/null 2>&1; then
    db_ready=true
    break
  fi
  sleep 2
done
if [[ "${db_ready}" != true ]]; then
  echo "ERROR: MariaDB did not become reachable with the configured Ragnarok database account." >&2
  exit 1
fi

# Confirm both pre-created databases are visible to this restricted SQL account.
visible_databases="$(MYSQL_PWD="${DB_PASSWORD}" mariadb -N -s -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME IN ('${DB_NAME}', '${LOG_DB_NAME}');")"
for database_name in "${DB_NAME}" "${LOG_DB_NAME}"; do
  if ! grep -Fxq -- "${database_name}" <<< "${visible_databases}"; then
    echo "ERROR: database '${database_name}' is missing or inaccessible. Create it and grant the dedicated Ragnarok SQL user access before starting rAthena." >&2
    exit 1
  fi
done

# Bootstrap schemas only when enabled and the target database has no tables.
# Existing/partially populated databases are never dropped, truncated, or re-imported.
if [[ "${AUTO_IMPORT_SQL,,}" == "true" ]]; then
  main_tables="$(MYSQL_PWD="${DB_PASSWORD}" mariadb -N -s -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -D "${DB_NAME}" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE();")"
  if [[ "${main_tables}" == "0" ]]; then
    echo "Importing rAthena main schema into empty database ${DB_NAME}."
    MYSQL_PWD="${DB_PASSWORD}" mariadb -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" "${DB_NAME}" < /rathena/sql-files/main.sql
  else
    echo "Database ${DB_NAME} already contains ${main_tables} table(s); leaving its schema untouched."
  fi
  log_tables="$(MYSQL_PWD="${DB_PASSWORD}" mariadb -N -s -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -D "${LOG_DB_NAME}" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE();")"
  if [[ "${log_tables}" == "0" ]]; then
    echo "Importing rAthena log schema into empty database ${LOG_DB_NAME}."
    MYSQL_PWD="${DB_PASSWORD}" mariadb -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" "${LOG_DB_NAME}" < /rathena/sql-files/logs.sql
  else
    echo "Database ${LOG_DB_NAME} already contains ${log_tables} table(s); leaving its schema untouched."
  fi
  # web.sql uses CREATE TABLE IF NOT EXISTS and is safe to apply repeatedly;
  # FluxCP uses these tables for web-side configuration and guild emblem data.
  echo "Ensuring rAthena web schema tables exist in ${DB_NAME}."
  MYSQL_PWD="${DB_PASSWORD}" mariadb -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" "${DB_NAME}" < /rathena/sql-files/web.sql
else
  echo "AUTO_IMPORT_SQL is disabled; skipping automatic schema initialization."
fi

echo "rAthena configuration prepared."
echo "Database endpoint: ${DB_HOST}:${DB_PORT}; databases: ${DB_NAME}, ${LOG_DB_NAME}"
echo "Advertised server address: ${SERVER_IP}; packet version is compiled into this image."
echo "NOTE: database schema import and public client-address configuration are separate setup steps."

# Run the three required daemons concurrently and stop the whole stack if any exits.
children=()
cleanup() {
  trap - TERM INT
  for pid in "${children[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup TERM INT EXIT

./login-server &
children+=("$!")
./char-server &
children+=("$!")
./map-server &
children+=("$!")

sleep 2
for pid in "${children[@]}"; do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "ERROR: one of the rAthena daemons exited during startup." >&2
    wait "$pid" || true
    exit 1
  fi
done

wait -n "${children[@]}"

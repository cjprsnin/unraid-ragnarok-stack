#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

cd /rathena
rm -f /tmp/rathena-ready

# Unraid bind mounts are commonly root-owned. Initialize and fix ownership once,
# then re-exec this script as the unprivileged rAthena account.
#
# Log sharing: the daemons run with umask 077 for config, but their log files must
# be readable by the optional supervisor container without becoming world-readable.
# The daemons therefore run as user "rathena" with primary group RAGNAROK_LOG_GID,
# log files are created 0640 (umask 027, set just before the daemons start), and the
# supervisor joins that same group. "Other" never gets any access.
: "${RAGNAROK_LOG_GID:=10100}"
case "${RAGNAROK_LOG_GID}" in
  ""|*[!0-9]*|0) echo "ERROR: RAGNAROK_LOG_GID must be a positive numeric group id (received: ${RAGNAROK_LOG_GID})." >&2; exit 64 ;;
esac

if [[ "$(id -u)" -eq 0 ]]; then
  mkdir -p conf save log
  if [[ ! -f conf/login_athena.conf || ! -f conf/char_athena.conf || ! -f conf/map_athena.conf ]]; then
    cp -an /usr/share/rathena-default-conf/. conf/
  fi
  chown -R rathena:rathena conf save
  # log/: owner rathena, group = shared log group, rwxr-s--- dirs and rw-r----- files
  # (also repairs files left at mode 600 by earlier runs). The setgid bit is a
  # best-effort extra; correctness does not depend on it because the daemons'
  # primary group is already the log group.
  chown -R "rathena:${RAGNAROK_LOG_GID}" log
  find log -type d -exec chmod 2750 {} +
  find log -type f -exec chmod 0640 {} +
  exec gosu "rathena:${RAGNAROK_LOG_GID}" "$0" "$@"
fi

: "${DB_HOST:=ragnarok-db}"
: "${DB_PORT:=3306}"
: "${DB_NAME:=ragnarok}"
: "${LOG_DB_NAME:=ragnarok_logs}"
: "${DB_USER:=ragnarok}"
: "${DB_PASSWORD:?Set DB_PASSWORD for the dedicated Ragnarok SQL user}"
: "${SERVER_IP:?Set SERVER_IP to the server LAN address}"
: "${AUTO_IMPORT_SQL:=true}"

case "${AUTO_IMPORT_SQL,,}" in
  true|false) ;;
  *) echo "ERROR: AUTO_IMPORT_SQL must be true or false (received: ${AUTO_IMPORT_SQL})." >&2; exit 64 ;;
esac

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

# Inter-server credentials. Upstream ships login/char/map servers with the public
# default s1/p1 (an account row in the `login` table with sex 'S'), which would let
# anyone who can reach the published ports register a rogue char server. We replace
# the password with a strong one. It comes from INTERSERVER_PASSWORD (set via
# RAGNAROK_INTERSERVER_PASSWORD in .env) or, when unset, is generated once and kept
# in conf/import/.interserver-password so every restart reuses it.
# rAthena limits the value to 23 characters; restricting it to letters and digits
# keeps it safe for the config parser and for the SQL statement below.
INTERSERVER_USERID="s1"
interserver_secret_file="conf/import/.interserver-password"
interserver_valid() { [[ "$1" =~ ^[A-Za-z0-9]{16,23}$ ]]; }

if [[ -n "${INTERSERVER_PASSWORD:-}" ]]; then
  INTERSERVER_PASSWORD_SOURCE="environment"
  if ! interserver_valid "${INTERSERVER_PASSWORD}"; then
    echo "ERROR: RAGNAROK_INTERSERVER_PASSWORD must be 16-23 letters/digits only (rAthena allows at most 23 characters). Generate one with: tr -dc 'A-Za-z0-9' </dev/urandom | head -c 23; echo" >&2
    exit 64
  fi
else
  INTERSERVER_PASSWORD=""
  if [[ -s "${interserver_secret_file}" ]]; then
    INTERSERVER_PASSWORD="$(head -n1 "${interserver_secret_file}")"
  fi
  if interserver_valid "${INTERSERVER_PASSWORD}"; then
    INTERSERVER_PASSWORD_SOURCE="stored in ${interserver_secret_file}"
  else
    INTERSERVER_PASSWORD=""
    while [[ ${#INTERSERVER_PASSWORD} -lt 23 ]]; do
      INTERSERVER_PASSWORD="$(head -c 64 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9')"
    done
    INTERSERVER_PASSWORD="${INTERSERVER_PASSWORD:0:23}"
    ( umask 077; printf '%s\n' "${INTERSERVER_PASSWORD}" > "${interserver_secret_file}" )
    INTERSERVER_PASSWORD_SOURCE="generated and stored in ${interserver_secret_file}"
  fi
fi

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
userid: ${INTERSERVER_USERID}
passwd: ${INTERSERVER_PASSWORD}
EOF

cat > conf/import/map_conf.txt <<EOF
// Managed by the container entrypoint.
map_ip: ${SERVER_IP}
userid: ${INTERSERVER_USERID}
passwd: ${INTERSERVER_PASSWORD}
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

# Keep the inter-server account row in step with the configuration above. This runs
# regardless of AUTO_IMPORT_SQL (that setting only controls schema bootstrap) and only
# ever UPDATEs the single s1 server row; nothing is dropped, truncated or inserted.
# The password is validated as letters/digits only, and is sent over stdin so it never
# appears in a process argument list.
login_table="$(MYSQL_PWD="${DB_PASSWORD}" mariadb -N -s -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -D "${DB_NAME}" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'login';")"
if [[ "${login_table}" != "1" ]]; then
  echo "WARNING: table 'login' not found in ${DB_NAME}; inter-server password not synchronized. Import the rAthena schema, then restart this container." >&2
else
  server_rows="$(MYSQL_PWD="${DB_PASSWORD}" mariadb -N -s -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -D "${DB_NAME}" -e "SELECT COUNT(*) FROM \`login\` WHERE account_id = 1 AND userid = '${INTERSERVER_USERID}' AND sex = 'S';")"
  if [[ "${server_rows}" == "1" ]]; then
    MYSQL_PWD="${DB_PASSWORD}" mariadb -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -D "${DB_NAME}" <<SQL
UPDATE \`login\` SET user_pass = '${INTERSERVER_PASSWORD}' WHERE account_id = 1 AND userid = '${INTERSERVER_USERID}' AND sex = 'S';
SQL
    echo "Inter-server account '${INTERSERVER_USERID}' is synchronized with the configured password."
  else
    echo "WARNING: inter-server row (account_id 1, userid '${INTERSERVER_USERID}', sex 'S') not found in ${DB_NAME}.login; the login server will reject the char server until a matching 'S' row exists." >&2
  fi
fi

echo "rAthena configuration prepared."
echo "Database endpoint: ${DB_HOST}:${DB_PORT}; databases: ${DB_NAME}, ${LOG_DB_NAME}"
echo "Advertised server address: ${SERVER_IP}; packet version is compiled into this image."
echo "Inter-server user: ${INTERSERVER_USERID}; password ${INTERSERVER_PASSWORD_SOURCE} (not shown)."
echo "NOTE: database schema import and public client-address configuration are separate setup steps."

# From here on, files created by the daemons (logs, saves) are group-readable by the
# log group only. Everything above (generated config containing the DB password) was
# created with umask 077 and stays private to the rathena user.
umask 027

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

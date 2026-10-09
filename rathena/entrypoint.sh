#!/usr/bin/env bash
set -Eeuo pipefail

cd /rathena

: "${DB_HOST:=ragnarok-db}"
: "${DB_PORT:=3306}"
: "${DB_NAME:=ragnarok}"
: "${LOG_DB_NAME:=ragnarok_logs}"
: "${DB_USER:=ragnarok}"
: "${DB_PASSWORD:?Set DB_PASSWORD for the dedicated Ragnarok SQL user}"
: "${SERVER_IP:?Set SERVER_IP to the server LAN address}"
: "${PACKETVER:=20200401}"

# A bind-mounted empty conf directory must not erase the upstream configuration.
if [[ ! -f conf/login-server.conf || ! -f conf/char-server.conf || ! -f conf/map-server.conf ]]; then
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
import: conf/import/inter_conf.txt
EOF

echo "rAthena configuration prepared."
echo "Database endpoint: ${DB_HOST}:${DB_PORT}; databases: ${DB_NAME}, ${LOG_DB_NAME}"
echo "Advertised server address: ${SERVER_IP}; PACKETVER=${PACKETVER}"
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

touch /tmp/rathena-ready
wait -n "${children[@]}"

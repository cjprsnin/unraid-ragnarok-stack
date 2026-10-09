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

echo "rAthena image is starting."
echo "Database host: ${DB_HOST}:${DB_PORT}; database: ${DB_NAME}; logs: ${LOG_DB_NAME}"
echo "Server advertised address: ${SERVER_IP}; PACKETVER=${PACKETVER}"
echo "This development entrypoint does not yet rewrite every upstream rAthena configuration safely."
echo "Review and configure conf/import and the login/char/map server configs before running a public server."

# Avoid silently starting with stock loopback settings that would make remote clients fail.
if ! grep -Rqs "DB_HOST" conf/import 2>/dev/null; then
  echo "ERROR: database config generation has not been implemented; refusing to start with possibly incorrect defaults." >&2
  exit 78
fi

touch /tmp/rathena-ready
exec bash -c './login-server && ./char-server && ./map-server'

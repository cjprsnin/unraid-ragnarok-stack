#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="ro-ci-${GITHUB_RUN_ID:-local}-$$"
APPDATA_ROOT="${RUNNER_TEMP:-/tmp}/ragnarok-stack-ci-${PROJECT}"
ENV_PATH="$ROOT_DIR/.env"

if [[ -e "$ENV_PATH" ]]; then
  echo "Refusing to overwrite an existing .env; integration tests need an isolated checkout." >&2
  exit 2
fi

cleanup() {
  docker compose -p "$PROJECT" -f docker-compose.yml -f docker-compose.ci.yml down -v --remove-orphans >/dev/null 2>&1 || true
  rm -f "$ENV_PATH"
  rm -rf "$APPDATA_ROOT"
}
trap cleanup EXIT

mkdir -p "$APPDATA_ROOT"
cat > "$ENV_PATH" <<EOF
SERVER_IP=127.0.0.1
DB_HOST=ragnarok-db
DB_PORT=3306
MARIADB_ROOT_PASSWORD=ci-root-password
RAGNAROK_DB_NAME=ragnarok
RAGNAROK_LOG_DB_NAME=ragnarok_logs
RAGNAROK_DB_USER=ragnarok
RAGNAROK_DB_PASSWORD=ci-test-password
FLUXCP_PORT=8088
SITE_TITLE=Ragnarok CI
FLUX_INSTALLER_PASSWORD=ci-installer-password
APPDATA_ROOT=$APPDATA_ROOT
AUTO_IMPORT_SQL=true
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen3:4b
EOF

echo "Building pinned rAthena image with generated renewal SQL..."
docker build --tag ragnarok-rathena:ci --file rathena/Dockerfile \
  --build-arg RATHENA_REF=d4b8e7b8f16061cc2496d377ac8f777ce72a4f39 \
  --build-arg PACKETVER=20200401 ./rathena

echo "Building pinned FluxCP image with upstream schema bootstrap..."
docker build --tag ragnarok-fluxcp:ci --file fluxcp/Dockerfile \
  --build-arg FLUXCP_REF=98cd4b8fd83228c11b36fb3d097b8e0f7c105a8d ./fluxcp

COMPOSE=(docker compose -p "$PROJECT" -f docker-compose.yml -f docker-compose.ci.yml)
"${COMPOSE[@]}" config -q

echo "Starting a fresh Compose project and waiting for healthy services..."
"${COMPOSE[@]}" up -d --wait --wait-timeout 300
"${COMPOSE[@]}" ps

db_query() {
  "${COMPOSE[@]}" exec -T database mariadb -N -s -uroot -pci-root-password -D ragnarok -e "$1"
}

item_count="$(db_query 'SELECT COUNT(*) FROM item_db_re;')"
red_potion="$(db_query "SELECT COUNT(*) FROM item_db_re WHERE id=501 AND name_english='Red Potion';")"
mob_count="$(db_query 'SELECT COUNT(*) FROM mob_db_re;')"
migration_count="$(db_query "SELECT COUNT(*) FROM schema_migrations WHERE name='renewal_item_mob_data_v1';")"

echo "Initial database: item_db_re=$item_count RedPotion=$red_potion mob_db_re=$mob_count migration=$migration_count"
test "$item_count" -gt 20000
test "$red_potion" -eq 1
test "$mob_count" -gt 1000
test "$migration_count" -eq 1

echo "Checking FluxCP item view, item search, and account-create pages..."
curl -fsSL "http://127.0.0.1:8088/?module=item&action=view&id=501" | grep -qi 'Red Potion'
curl -fsSL "http://127.0.0.1:8088/?module=item&action=index&name=Red" | grep -qi 'Red Potion'
curl -fsSL "http://127.0.0.1:8088/?module=account&action=create" >/dev/null

before="$item_count"
echo "Restarting rAthena to verify the migration is idempotent..."
"${COMPOSE[@]}" restart rathena
"${COMPOSE[@]}" up -d --wait --wait-timeout 180 rathena

after="$(db_query 'SELECT COUNT(*) FROM item_db_re;')"
migration_after="$(db_query "SELECT COUNT(*) FROM schema_migrations WHERE name='renewal_item_mob_data_v1';")"
test "$before" = "$after"
test "$migration_after" -eq 1
echo "PASS: renewal item data survived restart ($after rows; ledger=$migration_after)."

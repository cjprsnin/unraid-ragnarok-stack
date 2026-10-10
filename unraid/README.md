# Unraid Compose Manager package

This directory documents how to deploy the repository's Compose stack with the Unraid Compose Manager plugin. The actual stack definition is the repository-root `docker-compose.yml`; do not use a single-container Community Applications XML template for this multi-service stack.

## Requirements

- Unraid with Docker and the Compose Manager plugin.
- The existing MariaDB container; this stack intentionally does **not** create a second database.
- The existing Docker network named `ragnarok`, with your MariaDB container attached under the network alias `ragnarok-db`.
- A dedicated MariaDB account with privileges limited to the `ragnarok` and `ragnarok_logs` databases.
- GHCR images published for this repository before using the current Compose file. The normal CI workflow only validates/builds and never publishes.

## Import

1. Clone or download this repository onto Unraid, for example under `/mnt/user/appdata/ragnarok/ragnarok-stack`.
2. Copy `.env.example` to `.env` in that folder.
3. Edit `.env`: set `SERVER_IP` to the Unraid LAN IP, replace both example passwords, and confirm `APPDATA_ROOT`. Keep `.env` private and never commit it.
4. Confirm the existing MariaDB container is on the `ragnarok` network with alias `ragnarok-db`. Do not create a second MariaDB service.
5. Import the repository-root `docker-compose.yml` into Compose Manager as a stack and set its working directory to the folder containing `.env`.
6. Run `docker compose config -q` from that folder before starting anything.
7. Start only `rathena` first. Inspect its logs and confirm the database schema and game-server daemons are healthy before starting `fluxcp`.

## Ports and optional services

- rAthena: TCP 6900 (login), 6121 (character), 5121 (map).
- FluxCP: host port `FLUXCP_PORT` (default 8080) to container port 80.
- OpenKore is opt-in with `--profile bot` / Compose Manager profile support.
- The Ollama supervisor is opt-in with `--profile supervisor` and is disabled by default.

## SQL safety

With `AUTO_IMPORT_SQL=true`, the rAthena entrypoint imports `main.sql` and `logs.sql` only when their target databases contain zero tables, then applies `web.sql` to ensure web tables exist. It does not drop or truncate existing tables, but back up both databases before the first run. Set `AUTO_IMPORT_SQL=false` to skip automatic SQL initialization.

## Current limitation

This package is still in development. The image validation workflow has passed, but the stack has not yet been end-to-end tested on an Unraid host. Do not expose FluxCP to the internet until authentication, HTTPS, and the deployment configuration have been reviewed.

# Unraid Ragnarok Stack

A Docker Compose starter for running a private rAthena server with FluxCP on Unraid.

> **Status: development / not yet production-ready.** The image build and game-server startup still need end-to-end testing. The guarded schema bootstrap only imports into empty databases; still back up your data before use.

## Design

- Uses an existing MariaDB container; this project does not deploy a second database.
- MariaDB must be attached to the Compose network with alias `ragnarok-db`.
- rAthena and FluxCP are the default services.
- OpenKore is opt-in with the `bot` profile.
- The Ollama log-analysis helper is opt-in with the `supervisor` profile and is disabled by default.
- Persistent data belongs under the configured Unraid appdata directory.
- FluxCP generates its initial application and database configuration from environment variables on first start; its config files then persist under appdata for manual customization.

## Before you start

1. Create a dedicated MariaDB user and the `ragnarok` and `ragnarok_logs` databases. The account should have privileges only on those databases. The rAthena entrypoint waits for MariaDB and, by default, imports the upstream `main.sql` and `logs.sql` schemas only when the respective database has zero tables. It also applies upstream `web.sql`, which uses `CREATE TABLE IF NOT EXISTS` to add missing web tables without dropping existing data. Set `AUTO_IMPORT_SQL=false` to disable all automatic SQL initialization. Back up your data before making changes.
2. Attach your existing MariaDB container to the `ragnarok` Docker network using alias `ragnarok-db`. Create the network first if needed:
   ```bash
   docker network create ragnarok
   docker network connect --alias ragnarok-db ragnarok YOUR_MARIADB_CONTAINER_NAME
   ```
3. Copy `.env.example` to `.env` and set unique strong passwords, your server LAN IP, and persistent paths.
4. Run `docker compose config -q` before starting anything.

## Images

The push-triggered GitHub Actions workflow is **validation-only** and never publishes images. A separate `Publish container images (manual)` workflow exists for a deliberate release: it requires a manual dispatch, an explicit confirmation checkbox, and a successful validation build before publishing `latest` and commit-SHA tags to GHCR. Only run it after runtime checks pass. GHCR package visibility may need to be changed to public before an Unraid server can pull the images without authentication. Your current Buildx version may need updating before source builds will work.

## Building locally

To build the images from this checkout instead of pulling from GHCR, layer `docker-compose.build.yml` over the main file:

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml build
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d rathena
```

Source refs and `PACKETVER` come from the Dockerfile `ARG` defaults, so local builds match CI. Override one per build, for example `docker compose -f docker-compose.yml -f docker-compose.build.yml build --build-arg PACKETVER=... rathena`.

> **Warning:** pass the same `-f docker-compose.yml -f docker-compose.build.yml` flags to every later compose command (`up`, `logs`, `ps`, `restart`, `down`, ...). Without the override, Compose uses the GHCR image names instead of the local `:local` images, and `up` will try to pull images that may not exist.

## Start

After the images have been built and published and the Compose file is configured to pull those published tags:

```bash
docker compose pull
docker compose up -d rathena
docker compose logs -f rathena
```

Start FluxCP only after rAthena's database setup and configuration have been verified:

```bash
docker compose up -d fluxcp
```

Optional services:

```bash
docker compose --profile bot up -d openkore
docker compose --profile supervisor up -d ollama-supervisor
```

The Ollama supervisor is advisory-only: it reads logs and writes reports; it must not execute game commands or modify configuration automatically.

### Supervisor scan behavior

Each cycle the supervisor looks at the newest 5 files under the log directory (`SCAN_NEWEST_FILES`) and only sends a file to Ollama if its modification time or size changed since its last successful analysis; failed analyses are retried next cycle. That bookkeeping is kept in `.supervisor-state.json` inside the reports directory, so a restart does not re-analyze unchanged files. Reports mirror the log tree (`char/char-server.log` is reported as `char/char-server.log.analysis.json`), so same-named files in different folders no longer overwrite each other; top-level files keep their old report names.

### Log and report permissions

rAthena logs are never world-readable. The rathena container runs its daemons as user `rathena` with primary group `RAGNAROK_LOG_GID` (default `10100`), creates log files as `0640` and log directories as `2750`, and the supervisor joins that numeric group as a supplementary group. The supervisor container starts as root only to fix ownership of the reports directory (which is usually root-owned on Unraid), then drops to a non-root uid/gid. Set `SUPERVISOR_UID`/`SUPERVISOR_GID` in `.env` to choose which owner the reports get (empty uses the image's `supervisor` user). Existing log files left at mode `600` by earlier runs are repaired the next time the rathena container starts, so restart `rathena` before the supervisor.

## Important

- Back up your MariaDB databases before importing upstream SQL schemas.
- The published rAthena image is compiled with `PACKETVER=20200401`. This is a build-time setting, not a runtime `.env` option; changing it requires rebuilding the rAthena image with a matching `PACKETVER` build argument and publishing/deploying that image. The client executable and server configuration must be compatible with that version.
- FluxCP's displayed game-server addresses use `SERVER_IP`, which must be reachable by game clients and users' browsers; do not set it to the internal Compose hostname `rathena`.
- Configure FluxCP according to its upstream documentation before exposing it outside your trusted LAN.
- Do not commit `.env`, credentials, game account passwords, or database dumps.

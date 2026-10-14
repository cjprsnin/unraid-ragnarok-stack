# Unraid Ragnarok Stack

A Docker Compose starter for running a private rAthena server with FluxCP on Unraid.

> **Status: development / not yet production-ready.** The image build and game-server startup still need end-to-end testing. The guarded schema bootstrap only imports into empty databases; still back up your data before use.

## Design

- Deploys its own MariaDB service on the private Compose network; no pre-existing database container or manual network connection is required.
- MariaDB creates the two Ragnarok databases and a dedicated least-scope SQL user on first initialization. The data directory is persistent.
- rAthena and FluxCP are the default services.
- OpenKore is opt-in with the `bot` profile.
- The Ollama log-analysis helper is opt-in with the `supervisor` profile and is disabled by default.
- Persistent data belongs under the configured Unraid appdata directory.
- FluxCP generates its initial application and database configuration from environment variables on first start; its config files then persist under appdata for manual customization.

## Before you start

1. Copy `.env.example` to `.env`.
2. Set unique strong values for `MARIADB_ROOT_PASSWORD`, `RAGNAROK_DB_PASSWORD`, and `FLUX_INSTALLER_PASSWORD`. Set `SERVER_IP` to the address game clients can reach. Keep secrets out of version control.
3. Run `docker compose config -q` to validate the configuration.
4. Start MariaDB and rAthena:

   ```bash
   docker compose pull
   docker compose up -d database rathena
   docker compose logs -f database rathena
   ```

5. Once rAthena is healthy, start FluxCP:

   ```bash
   docker compose up -d fluxcp
   ```

On first startup, MariaDB creates the `ragnarok` and `ragnarok_logs` databases and a dedicated SQL account. The rAthena entrypoint imports `main.sql` and `logs.sql` only when the respective databases contain zero tables, and applies upstream `web.sql` using `CREATE TABLE IF NOT EXISTS`. Existing or partially populated databases are not automatically reset. Set `AUTO_IMPORT_SQL=false` to disable rAthena's automatic schema initialization.

The included database is isolated on the Compose network and does not require a pre-existing MariaDB container or manually created Docker network.

## Images

The push-triggered GitHub Actions workflow is **validation-only** and never publishes images. A separate `Publish container images (manual)` workflow exists for a deliberate release: it requires a manual dispatch, an explicit confirmation checkbox, and a successful validation build before publishing `latest` and commit-SHA tags to GHCR. Only run it after runtime checks pass. GHCR package visibility may need to be changed to public before an Unraid server can pull the images without authentication. This repository does not yet provide a working local-build Compose profile; your current Buildx version may also need updating before source builds will work.

## Start

After the images have been built and published and the Compose file is configured to pull those published tags:

```bash
docker compose pull
docker compose up -d database rathena
docker compose logs -f database rathena
```

FluxCP waits for rAthena to report healthy:

```bash
docker compose up -d fluxcp
```

Optional services:

```bash
docker compose --profile bot up -d openkore
docker compose --profile supervisor up -d ollama-supervisor
```

The Ollama supervisor is advisory-only: it reads logs and writes reports; it must not execute game commands or modify configuration automatically.

## Important

- The included MariaDB service stores its data under `${APPDATA_ROOT}/database/data`. Do not remove this directory when upgrading. The root and game-account credentials are applied at first initialization; changing `.env` later does not rotate passwords inside an existing database volume.
- `docker compose down` preserves database files. `docker compose down -v` is not a reset for this bind-mounted data and does not erase it. To intentionally reset a disposable installation, stop the stack and remove its database data directory only after confirming the path and backups.
- MariaDB data persists under `${APPDATA_ROOT}/database/data`. Root and game-account credentials are applied at first initialization; changing `.env` later does not rotate passwords in an existing database volume. Back up databases before schema changes.
- `docker compose down` does not delete the bind-mounted database files. For an intentional disposable reset, stop the stack and remove only the verified database data directory after confirming backups.
- The published rAthena image is compiled with `PACKETVER=20200401`. This is a build-time setting, not a runtime `.env` option; changing it requires rebuilding the rAthena image with a matching `PACKETVER` build argument and publishing/deploying that image. The client executable and server configuration must be compatible with that version.
- FluxCP's displayed game-server addresses use `SERVER_IP`, which must be reachable by game clients and users' browsers; do not set it to the internal Compose hostname `rathena`.
- Configure FluxCP according to its upstream documentation before exposing it outside your trusted LAN.
- Do not commit `.env`, credentials, game account passwords, or database dumps.

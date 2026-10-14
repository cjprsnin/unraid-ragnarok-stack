# Unraid Ragnarok Stack

A Docker Compose starter for running a private rAthena server with FluxCP on Unraid.

> **Status: development / not yet production-ready.** CI validates Compose/XML, fresh MariaDB initialization, a clean rAthena + FluxCP image integration, renewal item row counts, FluxCP item/account pages, and item-data persistence across an rAthena restart. A successful CI run is not a substitute for a clean Unraid install test. Existing databases are not automatically reset; back up data before use.

## Design

- Deploys its own MariaDB service on the private Compose network; no pre-existing database container or manual network connection is required.
- MariaDB creates the two Ragnarok databases and a dedicated least-scope SQL user on first initialization. The data directory is persistent.
- rAthena and FluxCP are the default services.
- OpenKore is opt-in with the `bot` profile.
- The Ollama log-analysis helper is opt-in with the `supervisor` profile and is disabled by default.
- Persistent data belongs under the configured Unraid appdata directory.
- FluxCP generates its initial application and database configuration from environment variables on first start; its config files then persist under appdata for manual customization.

## Unraid compatibility and installation path

The target is **Unraid 7.x and newer**. The database, rAthena, and FluxCP are deployed together as one Compose stack; they are not three separate app templates.

- **Unraid 7.x:** install **Compose Manager Plus** from Community Apps, create one stack, paste in `unraid/compose/compose.yaml`, and copy the values from `unraid/compose/.env.example` into the stack's ENV editor. This is a separate prerequisite because Unraid 7 does not support the native Community Apps Compose-package installer contract. Compose Manager Plus lists Unraid 6.9.0+ as a requirement, but its current listing says versions older than 7.2.3 are not tested; those older releases are not verified by this project.
- **Unraid 8+:** the Community Apps template in `templates/ragnarok-stack.xml` declares the native Compose-package installer contract and points to the versioned package in `unraid/compose/`.

We will not use a privileged “installer” container with access to the host Docker socket to simulate one-click installation. The native Community Apps Compose package is the simplest path on Unraid 8+. On Unraid 7.x, Compose Manager Plus must be installed first, after which the whole game stack is managed as one project.

**Release status:** the repository and GHCR images remain private during development. A public Community Apps listing is not ready until the license is selected, the repository and images are deliberately made accessible, and clean-install/runtime testing passes.

## Before you start (manual Compose workflow)

1. Copy `.env.example` to `.env`.
2. Set unique strong values for `MARIADB_ROOT_PASSWORD`, `RAGNAROK_DB_PASSWORD`, and `FLUX_INSTALLER_PASSWORD`. For `RAGNAROK_DB_PASSWORD`, use only letters, numbers, and `_!@#%+=.,:-` (the initializer validates this because the value is embedded in SQL). Set `SERVER_IP` to the address game clients can reach. Keep secrets out of version control.
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

On first startup, MariaDB creates the `ragnarok` and `ragnarok_logs` databases and a dedicated SQL account. The rAthena entrypoint imports `main.sql` and `logs.sql` only when the respective databases contain zero tables, and applies upstream `web.sql` using `CREATE TABLE IF NOT EXISTS`. The image build runs the pinned revision's `yaml2sql` converter and packages the generated renewal item data. On first startup, the entrypoint creates the item table schemas only when missing, seeds empty item tables, verifies at least 20,000 renewal items including Red Potion (ID 501), and records the successful item migration in MariaDB. It does not re-run the item import on container recreation. If an unrecorded item table contains a partial data set, startup fails closed rather than dropping or silently replacing it. Existing main/log schemas are not automatically reset. Set `AUTO_IMPORT_SQL=false` to disable automatic schema and item-data initialization.

The included database is isolated on the Compose network and does not require a pre-existing MariaDB container or manually created Docker network.

## Images

The push-triggered GitHub Actions workflow is **validation-only** and never publishes images. A separate `Publish container images (manual)` workflow exists for a deliberate release: it requires a manual dispatch, an explicit confirmation checkbox, and a successful validation build before publishing `latest` and commit-SHA tags to GHCR. Only run it after runtime checks pass. GHCR package visibility may need to be changed to public before an Unraid server can pull the images without authentication. This repository does not yet provide a working local-build Compose profile; the build environment may also need a newer Buildx version before source builds will work.

## Optional services

```bash
docker compose --profile bot up -d openkore
docker compose --profile supervisor up -d ollama-supervisor
```

The Ollama supervisor is advisory-only: it reads logs and writes reports; it must not execute game commands or modify configuration automatically.

## Important

- The included MariaDB service stores its data under `${APPDATA_ROOT}/database/data`. Do not remove this directory when upgrading. The root and game-account credentials are applied at first initialization; changing `.env` later does not rotate passwords inside an existing database volume.
- `docker compose down` preserves database files. `docker compose down -v` does not erase this bind-mounted data. To intentionally reset a disposable installation, stop the stack and remove its database data directory only after confirming the path and backups.
- The published rAthena image is compiled with `PACKETVER=20200401`. This is a build-time setting, not a runtime `.env` option; changing it requires rebuilding the rAthena image with a matching `PACKETVER` build argument and publishing/deploying that image. The client executable and server configuration must be compatible with that version.
- FluxCP's displayed game-server addresses use `SERVER_IP`, which must be reachable by game clients and users' browsers; do not set it to the internal Compose hostname `rathena`.
- Configure FluxCP according to its upstream documentation before exposing it outside your trusted LAN.
- Do not commit `.env`, credentials, game account passwords, or database dumps.

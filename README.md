# Unraid Ragnarok Stack

A Docker Compose starter for running a private rAthena server with FluxCP on Unraid.

> **Status: development / not yet production-ready.** The image build and game-server startup still need end-to-end testing. Do not point this at a production game database until backups and schema-import behavior are verified.

## Design

- Uses an existing MariaDB container; this project does not deploy a second database.
- MariaDB must be attached to the Compose network with alias `ragnarok-db`.
- rAthena and FluxCP are the default services.
- OpenKore is opt-in with the `bot` profile.
- The Ollama log-analysis helper is opt-in with the `supervisor` profile and is disabled by default.
- Persistent data belongs under the configured Unraid appdata directory.

## Before you start

1. Create a dedicated MariaDB user and the `ragnarok` and `ragnarok_logs` databases. The account should have privileges only on those databases.
2. Attach your existing MariaDB container to the `ragnarok` Docker network using alias `ragnarok-db`. Create the network first if needed:
   ```bash
   docker network create ragnarok
   docker network connect --alias ragnarok-db ragnarok YOUR_MARIADB_CONTAINER_NAME
   ```
3. Copy `.env.example` to `.env` and set unique strong passwords, your server LAN IP, and persistent paths.
4. Run `docker compose config -q` before starting anything.

## Images

Images are intended to be published to GHCR by GitHub Actions. Until a successful workflow run publishes them, use the source-build configuration only if your Docker Buildx version supports it. Do not assume a `:latest` image exists before the workflow succeeds.

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

## Important

- Back up your MariaDB databases before importing upstream SQL schemas.
- The client packet version, client executable, and server configuration must be compatible.
- Configure FluxCP according to its upstream documentation before exposing it outside your trusted LAN.
- Do not commit `.env`, credentials, game account passwords, or database dumps.

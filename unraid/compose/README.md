# Ragnarok Stack — Unraid Compose package

This directory is the self-contained Compose source package for Unraid's native Community Apps Compose installer on Unraid 8. The package includes `compose.yaml`, `.env.example`, and the MariaDB first-initialization script it mounts.

## Unraid 7.x

Unraid 7 does not use the native Community Apps Compose-package contract. Install Compose Manager Plus from Community Apps first. The Compose file mounts `./database/init/01-create-ragnarok-databases.sh`, so do not paste only the YAML into a blank stack. Keep this complete directory on the array with `compose.yaml`, `.env`, and `database/init/01-create-ragnarok-databases.sh` together, then register the file in Compose Manager Plus (use its Indirect Path option if it is outside the default projects folder) and configure the matching `.env` path in the stack settings. For a test install, set `APPDATA_ROOT` to an isolated directory such as `/mnt/user/appdata/ragnarok-test/data`. Save and start the stack from Compose Manager Plus.

Compose Manager Plus lists Unraid 6.9.0+ as its requirement, but reports that versions older than 7.2.3 are not currently tested. Do not consider those earlier releases verified until tested.

## Configure

1. Copy `.env.example` to `.env`.
2. Set `SERVER_IP` to the address game clients can reach.
3. Set unique values for `MARIADB_ROOT_PASSWORD`, `RAGNAROK_DB_PASSWORD`, and `FLUX_INSTALLER_PASSWORD`. For `RAGNAROK_DB_PASSWORD`, use only letters, numbers, and `_!@#%+=.,:-`.
4. Review `APPDATA_ROOT` and the published ports before starting the stack.

The database directory persists under `APPDATA_ROOT/database/data`. Back it up before any schema change. The stack uses its own MariaDB service and does not depend on an existing database container.

## Release note

The Community Apps template pins a specific Compose source commit so the installer receives a reproducible package. Update `ComposeSourceCommit` when cutting a new release after validating the packaged Compose files. The GitHub repository and GHCR images remain private during development; this package is not ready for public installation until those are deliberately made accessible.

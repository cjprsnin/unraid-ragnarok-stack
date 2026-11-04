#!/bin/sh
set -eu

# Starts as root only long enough to fix ownership of the (often root-owned) reports
# bind mount, then drops privileges, mirroring the rathena container.
#
# Logs are shared via a numeric group: the rathena container writes logs as
# group RAGNAROK_LOG_GID with mode 0640, and this process joins that group as a
# supplementary group. Logs are never made world-readable.
if [ "$(id -u)" -eq 0 ]; then
  REPORT_DIR="${REPORT_DIR:-/reports}"
  uid="${SUPERVISOR_UID:-$(id -u supervisor)}"
  gid="${SUPERVISOR_GID:-$(id -g supervisor)}"
  log_gid="${RAGNAROK_LOG_GID:-10100}"

  for value in "$uid" "$gid" "$log_gid"; do
    case "$value" in
      ""|*[!0-9]*) echo "ERROR: SUPERVISOR_UID, SUPERVISOR_GID and RAGNAROK_LOG_GID must be numeric (received: '$value')." >&2; exit 64 ;;
    esac
  done
  if [ "$uid" -eq 0 ] || [ "$log_gid" -eq 0 ]; then
    echo "ERROR: refusing to run the supervisor as uid 0 or with log group 0." >&2
    exit 64
  fi

  mkdir -p "$REPORT_DIR"
  chown -R "$uid:$gid" "$REPORT_DIR"
  chmod 750 "$REPORT_DIR"

  umask 027
  exec setpriv --reuid "$uid" --regid "$gid" --groups "$log_gid" -- "$@"
fi

exec "$@"

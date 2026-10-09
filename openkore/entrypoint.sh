#!/usr/bin/env sh
set -eu
: "${RO_USER:?Set RO_USER only if you intend to run your own OpenKore bot account}"
: "${RO_PASS:?Set RO_PASS only if you intend to run your own OpenKore bot account}"
echo "OpenKore is an optional profile. Configure its server entry and bot behavior for your own private server."
echo "This image does not auto-login or generate a bot control file."
exec sleep infinity

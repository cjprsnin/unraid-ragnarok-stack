#!/usr/bin/env sh
set -eu
cd /var/www/html

if [ ! -f /var/www/html/config/application.php ] && [ ! -f /var/www/html/config/servers.php ]; then
  echo "NOTICE: FluxCP upstream configuration has not been installed."
  echo "Follow the current FluxCP documentation to configure database connections and server settings before exposing this site."
fi

exec "$@"

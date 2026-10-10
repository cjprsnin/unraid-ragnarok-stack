#!/usr/bin/env sh
set -eu
umask 077
cd /var/www/html

mkdir -p /var/www/html/config /var/www/html/data

# The Unraid config bind mount hides the image's config directory. Keep the
# upstream defaults in /usr/share and generate environment-backed wrappers
# only on first boot, so existing user edits are preserved.
if [ ! -f /var/www/html/config/application.php ]; then
  cat > /var/www/html/config/application.php <<'PHP'
<?php
$config = require '/usr/share/fluxcp-default-config/application.php';
$config['ServerAddress'] = (getenv('SERVER_IP') ?: 'localhost') . ':' . (getenv('FLUXCP_PORT') ?: '8080');
$config['BaseURI'] = '';
$config['ForceHTTPS'] = false;
$config['InstallerPassword'] = getenv('INSTALLER_PASSWORD') ?: 'CHANGE_ME';
$config['SiteTitle'] = getenv('SITE_TITLE') ?: 'Ragnarok Control Panel';
return $config;
PHP
fi

if [ ! -f /var/www/html/config/servers.php ]; then
  cat > /var/www/html/config/servers.php <<'PHP'
<?php
$servers = require '/usr/share/fluxcp-default-config/servers.php';
$dbHost = getenv('DB_HOST') ?: 'ragnarok-db';
$dbPort = (int) (getenv('DB_PORT') ?: 3306);
$dbName = getenv('DB_NAME') ?: 'ragnarok';
$logDbName = getenv('LOG_DB_NAME') ?: 'ragnarok_logs';
$dbUser = getenv('DB_USER') ?: 'ragnarok';
$dbPassword = getenv('DB_PASSWORD') ?: '';
$rathenaHost = getenv('RATHENA_HOST') ?: 'rathena';

foreach ($servers as &$server) {
    foreach (['DbConfig' => $dbName, 'LogsDbConfig' => $logDbName, 'WebDbConfig' => $dbName] as $key => $database) {
        $server[$key]['Hostname'] = $dbHost;
        $server[$key]['Port'] = $dbPort;
        $server[$key]['Username'] = $dbUser;
        $server[$key]['Password'] = $dbPassword;
        $server[$key]['Database'] = $database;
    }
    $server['LoginServer']['Address'] = $rathenaHost;
    foreach ($server['CharMapServers'] as &$pair) {
        $pair['CharServer']['Address'] = $rathenaHost;
        $pair['MapServer']['Address'] = $rathenaHost;
    }
    unset($pair);
}
unset($server);
return $servers;
PHP
fi

# Ensure FluxCP can write its data/cache tree when using Unraid bind mounts.
chown -R www-data:www-data /var/www/html/config /var/www/html/data
find /var/www/html/config -type f -exec chmod 600 {} \;
exec "$@"

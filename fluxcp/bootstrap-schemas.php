<?php
declare(strict_types=1);

define('FLUX_ROOT', str_replace('\\\\', '/', dirname(__DIR__, 2) . '/var/www/html'));
define('FLUX_DATA_DIR', 'data');
define('FLUX_CONFIG_DIR', 'config');
define('FLUX_LIB_DIR', 'lib');
define('FLUX_MODULE_DIR', 'modules');
define('FLUX_THEME_DIR', 'themes');
define('FLUX_ADDON_DIR', 'addons');
define('FLUX_LANG_DIR', 'lang');

chdir('/var/www/html');
set_include_path(FLUX_LIB_DIR . PATH_SEPARATOR . get_include_path());

require_once FLUX_CONFIG_DIR . '/groups.php';
require_once 'Flux.php';
require_once 'Flux/DataObject.php';
require_once 'Flux/Installer.php';

Flux::initialize(array(
    'appConfigFile'           => FLUX_CONFIG_DIR . '/application.php',
    'serversConfigFile'       => FLUX_CONFIG_DIR . '/servers.php',
    'appConfigFileImport'     => FLUX_CONFIG_DIR . '/import/application.php',
    'serversConfigFileImport' => FLUX_CONFIG_DIR . '/import/servers.php',
));

$directories = array(
    FLUX_DATA_DIR . '/logs/schemas',
    FLUX_DATA_DIR . '/logs/schemas/logindb',
    FLUX_DATA_DIR . '/logs/schemas/charmapdb',
    FLUX_DATA_DIR . '/logs/transactions',
    FLUX_DATA_DIR . '/logs/mail',
    FLUX_DATA_DIR . '/logs/mysql',
    FLUX_DATA_DIR . '/logs/mysql/errors',
    FLUX_DATA_DIR . '/logs/errors',
    FLUX_DATA_DIR . '/logs/errors/exceptions',
    FLUX_DATA_DIR . '/logs/errors/mail',
);

foreach (Flux::$loginAthenaGroupRegistry as $serverName => $loginAthenaGroup) {
    $directories[] = FLUX_DATA_DIR . "/logs/schemas/logindb/$serverName";
    $directories[] = FLUX_DATA_DIR . "/logs/schemas/charmapdb/$serverName";

    foreach (Flux::$athenaServerRegistry[$serverName] ?? array() as $athenaServer) {
        $directories[] = FLUX_DATA_DIR . "/logs/schemas/charmapdb/$serverName/{$athenaServer->serverName}";
    }
}

foreach ($directories as $directory) {
    if (!is_dir($directory) && !mkdir($directory, 0700, true) && !is_dir($directory)) {
        throw new RuntimeException("Unable to create FluxCP schema directory: $directory");
    }
}

$dbHost = getenv('DB_HOST') ?: 'ragnarok-db';
$dbPort = (int) (getenv('DB_PORT') ?: 3306);
$dbName = getenv('DB_NAME') ?: 'ragnarok';
$dbUser = getenv('DB_USER') ?: 'ragnarok';
$dbPassword = getenv('DB_PASSWORD') ?: '';

$pdo = new PDO(
    "mysql:host=$dbHost;port=$dbPort;dbname=$dbName;charset=utf8mb4",
    $dbUser,
    $dbPassword,
    array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC)
);

$markers = array_merge(
    glob(FLUX_DATA_DIR . '/logs/schemas/logindb/*/*.txt') ?: array(),
    glob(FLUX_DATA_DIR . '/logs/schemas/charmapdb/*/*/*.txt') ?: array()
);
$existingFluxTables = (int) $pdo->query(
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND LEFT(table_name, 3) = 'cp_'"
)->fetchColumn();

// If someone points a new FluxCP data directory at a database with hand-created
// FluxCP tables, do not blindly replay every historical ALTER migration. Let the
// administrator use FluxCP's own installer/updater to reconcile that database.
if (!$markers && $existingFluxTables > 0) {
    fwrite(STDOUT, "FluxCP schema bootstrap skipped: existing cp_ tables have no upstream schema markers; preserving the database. Use the FluxCP installer to reconcile its schema.\\n");
    exit(0);
}

$installer = Flux_Installer::getInstance();
$installer->updateAll();

if ($installer->updateNeeded()) {
    throw new RuntimeException('FluxCP schema initialization did not reach the latest upstream schema versions.');
}

$requiredTables = array('cp_itemshop', 'cp_cmsnews', 'cp_cmspages', 'cp_cmssettings');
foreach ($requiredTables as $table) {
    $statement = $pdo->prepare(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = :table'
    );
    $statement->execute(array(':table' => $table));
    if ((int) $statement->fetchColumn() !== 1) {
        throw new RuntimeException("FluxCP schema initialization completed but required table '$table' is missing.");
    }
}

fwrite(STDOUT, "FluxCP upstream schema initialization is current; required CMS and item-shop tables exist.\\n");

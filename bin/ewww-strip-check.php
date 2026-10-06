<?php
// Run inside the web-server container with EWWW active: the three conditions EWWW
// checks before it adds -strip all to optipng (unique.php, PNG branch).
define('WP_ADMIN', true);
require '/var/www/html/wp-load.php';
$tools = ewwwio()->local->check_all_tools();
$optipng = $tools['OPTIPNG']['path'] ?? ($tools['optipng'] ?? '');
if (is_array($optipng)) { $optipng = $optipng['path'] ?? ''; }
$version = $optipng ? ewwwio()->local->test_binary($optipng, 'optipng') : '';
echo 'ewww: ', EWWW_IMAGE_OPTIMIZER_VERSION, "\n";
echo 'optipng path: ', var_export($optipng, true), "\n";
echo 'test_binary() returned: ', var_export($version, true), "\n";
echo "preg_match('/0.7/', that): ", var_export(preg_match('/0.7/', (string) $version), true), "\n";
echo 'metadata_remove: ', var_export(ewww_image_optimizer_get_option('ewww_image_optimizer_metadata_remove'), true), "\n";
echo 'metadata_skip_full: ', var_export(ewww_image_optimizer_get_option('ewww_image_optimizer_metadata_skip_full'), true), "\n";
echo 'optipng -v, first lines:', "\n", $optipng ? implode("\n", array_slice(explode("\n", (string) shell_exec(escapeshellarg($optipng) . ' -v 2>&1')), 0, 4)) : '-', "\n";

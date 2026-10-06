<?php
// Runs inside the web-server container: an upload as the browser's route makes it
// (wp_handle_sideload + wp_generate_attachment_metadata through media_handle_sideload).
define('WP_ADMIN', true);
require '/var/www/html/wp-load.php';
require_once ABSPATH.'wp-admin/includes/file.php';
require_once ABSPATH.'wp-admin/includes/media.php';
require_once ABSPATH.'wp-admin/includes/image.php';
wp_set_current_user(1);
$src = $argv[1];
$tmp = wp_tempnam(basename($src));
copy($src, $tmp);
$id = media_handle_sideload(['name' => basename($src), 'tmp_name' => $tmp], 0, $argv[2] ?? null);
if (is_wp_error($id)) { fwrite(STDERR, $id->get_error_message()."\n"); exit(1); }
echo $id, "\n";
echo 'editor: ', _wp_image_editor_choose(['mime_type' => get_post_mime_type($id)]), "\n";

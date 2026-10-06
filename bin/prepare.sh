#!/bin/bash
# Makes the web-server container behave like an ordinary host. Run once after
# `npm run env:start`; the changes are lost when the containers are rebuilt.
#  - optipng, pngquant, gifsicle, cwebp, jpegtran: the local tools image
#    plugins look for;
#  - wp-content and its uploads writable for the web server;
#  - a forward of port $PORT to the web server inside the container, so that
#    WordPress's requests to itself (WP-Cron, background jobs) arrive. Without
#    it, wp-env's site URL points at a port that only exists on the host.
set -eu
source "$(dirname "$0")/env.sh"
docker exec -u root "$WEB" sh -c 'apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libjpeg-turbo-progs optipng gifsicle webp pngquant socat >/dev/null'
# On Linux the checkout's files belong to the host user, and the web server (www-data)
# cannot write uploads or EWWW's tools; Docker Desktop on macOS hides this
docker exec -u root "$WEB" sh -c 'mkdir -p /var/www/html/wp-content/uploads && chmod -R a+rwX /var/www/html/wp-content/uploads && chmod a+rwx /var/www/html/wp-content'
docker exec -u root "$WEB" sh -c "pgrep -f 'socat TCP-LISTEN:$PORT' >/dev/null || (nohup socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:80 >/dev/null 2>&1 &)"
sleep 1
docker exec "$WEB" php -r 'echo "Imagick: ", Imagick::getVersion()["versionString"], "; JPEG ", count(Imagick::queryFormats("JPEG")), " WEBP ", count(Imagick::queryFormats("WEBP")), " AVIF ", count(Imagick::queryFormats("AVIF")), PHP_EOL;'
docker exec "$WEB" sh -c "curl -s -o /dev/null -w 'loopback to :$PORT inside the container: %{http_code}\n' http://localhost:$PORT/wp-login.php"

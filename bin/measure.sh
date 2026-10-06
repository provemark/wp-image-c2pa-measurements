#!/bin/bash
# One configuration, one image: upload it as the browser does, let background
# jobs run, then check every file WordPress and the plugin wrote, and every
# image URL the page hands a visitor, for C2PA Content Credentials.
#
# Usage: bin/measure.sh <out-dir> <fixture> [plugin-slug[@version]]
#   SETUP='php code'   run with `wp eval` after activation (one setting, say)
#   WAIT=seconds       how long to keep WP-Cron going after the upload (30)
#   POST='php code'    run with `wp eval` before cleaning up, {ID} = the attachment;
#                      its output goes to after.txt (a plugin's own record, say)
set -u
source "$(dirname "$0")/env.sh"
OUT=$1; FIXTURE=$2; PLUGIN=${3:-}; SETUP=${SETUP:-}; WAIT=${WAIT:-30}; POST=${POST:-}
MEASURED="webp-uploads ewww-image-optimizer webp-converter-for-media webp-express wp-smushit wp-optimize resmushit-image-optimizer"
mkdir -p "$OUT"; WORK=$ROOT/work/$(basename "$OUT"); rm -rf "$WORK"; mkdir -p "$WORK"
w() { docker exec "$CLI" wp "$@" 2>/dev/null; }

for p in $MEASURED; do w plugin deactivate "$p" >/dev/null; done
{
  echo "date: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "wordpress: $(w core version), php: $(docker exec "$WEB" php -r 'echo PHP_VERSION;')"
  if [ -n "$PLUGIN" ]; then
    slug=${PLUGIN%@*}; version=${PLUGIN#*@}; [ "$version" = "$PLUGIN" ] && version=
    w plugin install "$slug" ${version:+--version="$version"} --force >/dev/null
    w plugin activate "$slug" >/dev/null
    echo "plugin: $slug $(w plugin get "$slug" --field=version)"
  else
    echo "plugin: none (WordPress only)"
  fi
  # as a site owner does after activating a plugin: open wp-admin once (some plugins write
  # their default settings on that first visit, not on activation); test login of wp-env
  jar=$WORK/cookies.txt
  curl -s -c "$jar" -o /dev/null --data 'log=admin&pwd=password&testcookie=1' -b 'wordpress_test_cookie=WP%20Cookie%20check' "http://localhost:$PORT/wp-login.php"
  echo "wp-admin visited: $(curl -s -b "$jar" -o /dev/null -w '%{http_code}' "http://localhost:$PORT/wp-admin/")"
  [ -n "$SETUP" ] && echo "setup: $SETUP" && w eval "$SETUP" >/dev/null
  echo "fixture: $FIXTURE ($(shasum -a 256 "$ROOT/fixtures/$FIXTURE" | cut -c1-16)…)"
} > "$OUT/config.txt"

docker exec "$WEB" sh -c 'touch /tmp/c2pa-marker; sleep 1'
docker cp "$ROOT/bin/sideload.php" "$WEB:/tmp/sideload.php" >/dev/null
RES=$(docker exec -u www-data "$WEB" php /tmp/sideload.php "/var/www/html/wp-content/c2pa-fixtures/$FIXTURE" 2>&1)
ID=$(echo "$RES" | head -1)
case "$ID" in ''|*[!0-9]*) echo "upload failed: $RES" >&2; echo "upload failed: $RES" >> "$OUT/config.txt"; exit 1;; esac
echo "$RES" | sed -n 2p >> "$OUT/config.txt"
end=$((SECONDS + WAIT))
# WP-Cron as an external job runs it: without ?doing_wp_cron, which WordPress only honours
# when it matches its own lock
while [ $SECONDS -lt $end ]; do curl -s -o /dev/null "http://localhost:$PORT/wp-cron.php"; sleep 5; done
echo "attachment: $ID" >> "$OUT/config.txt"

w eval "echo apply_filters('the_content', wp_get_attachment_image($ID, 'large'));" > "$OUT/frontend.html"

check() {  # file -> "format c2pa state codes"
  $VERIFY "$1" 2>/dev/null | jq -r '[.format, (if .has_manifest then "yes" else "no" end), (if .has_manifest then .validation_state else "-" end), ([.validation_results.activeManifest.failure[]?.code | select(. != "signingCredential.untrusted" and . != "signingCredential.expired")] | join(",") | if . == "" then "-" else . end)] | join(" ")'
}

printf "%-72s %9s %-8s %-4s %-8s %s\n" "file written (under wp-content/)" bytes format c2pa state failures > "$OUT/files.txt"
docker exec "$WEB" sh -c 'cd /var/www/html && find wp-content -type f -newer /tmp/c2pa-marker \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.avif" -o -iname "*.gif" \) | sort' > "$WORK/written.txt"
while read -r f; do
  local_copy=$WORK/$(echo "$f" | tr '/' '_')
  docker exec "$WEB" cat "/var/www/html/$f" > "$local_copy"
  printf "%-72s %9s %s\n" "${f#wp-content/}" "$(wc -c < "$local_copy" | tr -d ' ')" "$(check "$local_copy")" >> "$OUT/files.txt"
done < "$WORK/written.txt"

printf "%-72s %9s %-8s %-4s %-8s %s\n" "served (Accept: image/avif,image/webp)" bytes format c2pa state failures > "$OUT/served.txt"
for u in $(grep -oE 'https?://[^" ,]+\.(jpe?g|png|gif|webp|avif)' "$OUT/frontend.html" | sort -u); do
  local_copy=$WORK/served_$(basename "$u")
  curl -s -H 'Accept: image/avif,image/webp,image/apng,image/*,*/*;q=0.8' -o "$local_copy" "$u"
  printf "%-72s %9s %s\n" "${u#*wp-content/}" "$(wc -c < "$local_copy" | tr -d ' ')" "$(check "$local_copy")" >> "$OUT/served.txt"
done

[ -n "$POST" ] && w eval "${POST//\{ID\}/$ID}" > "$OUT/after.txt"

# leave the site as it was: the attachment, and every file this run wrote
w post delete "$ID" --force >/dev/null
while read -r f; do docker exec "$WEB" rm -f "/var/www/html/$f"; done < "$WORK/written.txt"
[ -n "$PLUGIN" ] && w plugin deactivate "${PLUGIN%@*}" >/dev/null
cat "$OUT/config.txt"; echo; cat "$OUT/files.txt"; echo; cat "$OUT/served.txt"

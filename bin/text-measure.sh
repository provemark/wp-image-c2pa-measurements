#!/bin/bash
# Text with C2PA Content Credentials (C2PA 2.4 §A.8, the manifest as invisible
# Unicode variation selectors) through WordPress: saved as a post over the REST
# API, as the block editor does, by an administrator and by an author (whose
# content WordPress filters), and uploaded as a .txt file. For each, the text is
# taken from what is stored, from what the API renders and from the page a
# visitor gets, and checked with a c2patool built with c2pa-rs's experimental
# `unstable_plain_text` feature (the stock c2patool doesn't read text yet).
#
# Usage: TEXT_C2PATOOL=/path/to/c2patool bin/text-measure.sh <out-dir>
#   TEXTS='plain-simple plain'  which signed texts (default both)
#   MU='php code'               installed as a must-use plugin for the run, then removed
#                               (a site setting to try, such as turning wptexturize off)
set -u
source "$(dirname "$0")/env.sh"
OUT=$1; mkdir -p "$OUT"; WORK=$ROOT/work/text; rm -rf "$WORK"; mkdir -p "$WORK"
T=${TEXT_C2PATOOL:?set TEXT_C2PATOOL to a c2patool built with unstable_plain_text}
w() { docker exec "$CLI" wp "$@" 2>/dev/null; }
API=http://localhost:$PORT/wp-json/wp/v2

verdict() {  # file -> "Valid" | "Invalid codes" | "no manifest"
  out=$("$T" "$1" 2>&1); json=$(echo "$out" | sed -n '/^{/,$p')
  if [ -n "$json" ]; then
    echo "$json" | jq -r '.validation_state + ([.validation_results.activeManifest.failure[]?.code | select(. != "signingCredential.untrusted")] | if length > 0 then " " + join(",") else "" end)'
  else
    echo "$out" | head -1 | sed 's/^Error: //'
  fi
}
selectors() {  # file -> number of variation selectors (U+FE00-FE0F, U+E0100-E01EF)
  php -r 'echo preg_match_all("/[\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}]/u", file_get_contents($argv[1]));' "$1"
}
row() {  # label file
  printf "%-44s %7s bytes  %6s selectors  same as signed: %-3s  %s\n" "$1" "$(wc -c < "$2" | tr -d ' ')" "$(selectors "$2")" \
    "$(cmp -s "$2" "$SIGNED" && echo yes || echo no)" "$(verdict "$2")" >> "$OUT/result.txt"
}

# an author, and an application password for each user (local test credentials, not kept)
w user get text-author >/dev/null || w user create text-author text-author@example.test --role=author >/dev/null
PASS_admin=$(w user application-password create admin "text-measure-$$" --porcelain | tail -1)
PASS_author=$(w user application-password create text-author "text-measure-$$" --porcelain | tail -1)
pass() { [ "$1" = admin ] && echo "$PASS_admin" || echo "$PASS_author"; }  # bash 3.2 has no associative arrays

{
  echo "date: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "wordpress: $(w core version), php: $(docker exec "$WEB" php -r 'echo PHP_VERSION;')"
  echo "c2patool: $("$T" --version) (unstable_plain_text)"
} > "$OUT/config.txt"
: > "$OUT/result.txt"

if [ -n "${MU:-}" ]; then
  printf '<?php\n// text-measure.sh, removed after the run\n%s\n' "$MU" > "$WORK/text-measure-mu.php"
  docker exec "$WEB" mkdir -p /var/www/html/wp-content/mu-plugins
  docker cp "$WORK/text-measure-mu.php" "$WEB:/var/www/html/wp-content/mu-plugins/text-measure-mu.php" >/dev/null
  echo "mu-plugin: $MU" >> "$OUT/config.txt"
fi

for name in ${TEXTS:-plain-simple plain}; do
  SIGNED=$ROOT/text-fixtures/$name-signed.txt
  echo "== $name ($(wc -c < "$SIGNED" | tr -d ' ') bytes, $(verdict "$SIGNED"))" >> "$OUT/result.txt"
  for u in admin text-author; do
    for form in classic block; do
      label="$name / $u / $form"; key=$WORK/${name}_${u}_${form}
      # the content as the editor would send it: as is (classic) or in a paragraph block
      php -r '$t = file_get_contents($argv[1]); echo $argv[2] === "block" ? "<!-- wp:paragraph -->\n<p>".$t."</p>\n<!-- /wp:paragraph -->" : $t;' "$SIGNED" "$form" > "$key.sent"
      jq -n --rawfile c "$key.sent" '{title: "text-measure", status: "publish", content: $c}' > "$key.json"
      id=$(curl -s -u "$u:$(pass "$u")" -H 'Content-Type: application/json' --data @"$key.json" "$API/posts" | jq -r '.id // empty')
      if [ -z "$id" ]; then echo "$label: save failed" >> "$OUT/result.txt"; continue; fi
      curl -s -u "$u:$(pass "$u")" "$API/posts/$id?context=edit" > "$key.get.json"
      # stored: the raw content, with the block wrapper taken off again
      jq -j '.content.raw' "$key.get.json" | php -r '$t = stream_get_contents(STDIN); if (preg_match("#^<!-- wp:paragraph -->\n<p>(.*)</p>\n<!-- /wp:paragraph -->$#s", $t, $m)) { $t = $m[1]; } echo $t;' > "$key.stored.txt"
      # rendered by the API, and the page a visitor gets: tags removed, entities decoded
      jq -j '.content.rendered' "$key.get.json" > "$key.rendered.html"
      curl -s "$(jq -r '.link' "$key.get.json")" > "$key.page.html"
      php -r 'echo trim(html_entity_decode(strip_tags(file_get_contents($argv[1])), ENT_QUOTES | ENT_HTML5, "UTF-8"), "\n");' "$key.rendered.html" > "$key.rendered.txt"
      row "$label: stored" "$key.stored.txt"
      row "$label: rendered (API)" "$key.rendered.txt"
      # the page: the theme adds its own text around the post, so instead of cutting the post
      # out of it, check that the API's rendered content appears in the page byte for byte
      if php -r 'exit(str_contains(file_get_contents($argv[1]), trim(file_get_contents($argv[2]))) ? 0 : 1);' "$key.page.html" "$key.rendered.html"; then
        echo "$label: page                       contains the rendered content byte for byte (same result as rendered)" >> "$OUT/result.txt"
      else
        echo "$label: page                       does NOT contain the rendered content byte for byte" >> "$OUT/result.txt"
      fi
      w post delete "$id" --force >/dev/null
    done
  done
  # the same text as a file in the Media Library
  docker cp "$ROOT/bin/sideload.php" "$WEB:/tmp/sideload.php" >/dev/null
  aid=$(docker exec -u www-data "$WEB" php /tmp/sideload.php "/var/www/html/wp-content/c2pa-text/$name-signed.txt" 2>&1 | head -1)
  case "$aid" in ''|*[!0-9]*) echo "$name / upload: $aid" >> "$OUT/result.txt";;
    *) f=$(w eval "echo get_attached_file($aid);"); docker exec "$WEB" cat "$f" > "$WORK/${name}_upload.txt"
       row "$name / uploaded .txt: file" "$WORK/${name}_upload.txt"
       curl -s "$(w eval "echo wp_get_attachment_url($aid);")" > "$WORK/${name}_upload_served.txt"
       row "$name / uploaded .txt: served" "$WORK/${name}_upload_served.txt"
       w post delete "$aid" --force >/dev/null;;
  esac
done

for u in admin text-author; do w user application-password delete "$u" --all >/dev/null; done
[ -n "${MU:-}" ] && docker exec "$WEB" rm -f /var/www/html/wp-content/mu-plugins/text-measure-mu.php
cat "$OUT/config.txt" "$OUT/result.txt"

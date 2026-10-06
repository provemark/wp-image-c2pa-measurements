#!/bin/bash
# Jetpack's image CDN (i0.wp.com, the Site Accelerator) with public signed
# images: each fetched directly and through the CDN, as a browser asks for it,
# resized and not. No WordPress needed. Writes results/<date>/jetpack-cdn.txt.
set -u
cd "$(dirname "$0")/.."
DATE=${DATE:-$(date -u +%Y-%m-%d)}
OUT=results/$DATE/jetpack-cdn.txt; mkdir -p "results/$DATE" work/cdn
VERIFY="php vendor/bin/c2pa-verify"
COMMIT=2d40bcdbc8d831be17cffa4516a323e264cba16c
SOURCES="
raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures/fixture-signed.jpg
raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures/adobe-20260425-lightroom-classic-church.jpg
raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures/openai-20260826-c2pa_2x.png
raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures/fixture-signed.png
raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures/c2pa-verifier-ai-parent-chain.png
raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures/fixture-signed.webp
raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures/fixture-signed.gif
raw.githubusercontent.com/richardwooding/c2pa/main/testdata/c2pa_2x_openai.png
"
check() {
  $VERIFY "$1" 2>/dev/null | jq -r '(.format) + " " + (if .has_manifest then .validation_state + " " + ([.validation_results.activeManifest.failure[]?.code | select(. != "signingCredential.untrusted" and . != "signingCredential.expired")] | join(",")) else "no-C2PA" end)'
}
pixels() {  # two images -> "pixels identical" or a count; PNG only
  php -r '$a=@imagecreatefromstring(file_get_contents($argv[1])); $b=@imagecreatefromstring(file_get_contents($argv[2])); if(!$a||!$b||imagesx($a)!=imagesx($b)||imagesy($a)!=imagesy($b)){echo "-";exit;} $d=0; for($y=0;$y<imagesy($a);$y++) for($x=0;$x<imagesx($a);$x++) if(imagecolorat($a,$x,$y)!==imagecolorat($b,$x,$y)) $d++; echo $d===0?"pixels-identical":"$d-pixels-differ";' "$1" "$2"
}
{
  echo "date: $(date -u +%Y-%m-%dT%H:%MZ)"
  printf "%-40s %-10s %-14s %10s  %-34s %s\n" source request served bytes verdict pixels
  for src in $SOURCES; do
    n=$(basename "$src"); o=work/cdn/orig_$n
    curl -fsS -o "$o" "https://$src" || continue
    printf "%-40s %-10s %-14s %10s  %-34s\n" "$n" direct "$(file -b --mime-type "$o")" "$(wc -c < "$o" | tr -d ' ')" "$(check "$o")"
    for req in "png/jpeg|image/png,image/jpeg,image/gif,*/*|" "webp|image/avif,image/webp,*/*|" "w=1024|image/png,image/jpeg,image/gif,*/*|?w=1024"; do
      IFS='|' read -r label accept query <<< "$req"
      c=work/cdn/cdn_${label//\//-}_$n
      curl -fsS -A 'Mozilla/5.0 (measurement; github.com/provemark)' -H "Accept: $accept" -o "$c" "https://i0.wp.com/$src$query" || continue
      printf "%-40s %-10s %-14s %10s  %-34s %s\n" "" "$label" "$(file -b --mime-type "$c")" "$(wc -c < "$c" | tr -d ' ')" "$(check "$c")" "$( [ "$label" = png/jpeg ] && pixels "$o" "$c")"
      sleep 0.5
    done
  done
} | tee "$OUT"

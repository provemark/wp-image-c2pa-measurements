#!/bin/bash
# Every configuration with every test image, into results/<date>/.
set -u
cd "$(dirname "$0")/.."
DATE=${DATE:-$(date -u +%Y-%m-%d)}
IMAGES="fixture-signed.jpg adobe-20260425-lightroom-classic-church.jpg openai-20260826-c2pa_2x.png"
run() {  # label plugin setup wait
  for img in $IMAGES; do
    SETUP=$3 WAIT=$4 bin/measure.sh "results/$DATE/$1/${img%.*}" "$img" $2 > /dev/null 2>&1
    echo "$1 / $img done"
  done
}
run core                   ""                         ""  30
run modern-image-formats   webp-uploads               ""  30
run converter-for-media    webp-converter-for-media   ""  30
run webp-express           webp-express               ""  30
run ewww-image-optimizer   ewww-image-optimizer       ""  60
run smush                  wp-smushit                 ""  60
# compression is off until it is turned on; its queue is scheduled on WP-Cron five minutes
# after the upload (wp_schedule_single_event(time() + 300, 'process_smush_tasks'))
run wp-optimize            wp-optimize                "update_option('wp-optimize-autosmush', 1);" 360
run resmushit              resmushit-image-optimizer  ""  60
php bin/summarize.php "results/$DATE" > "results/$DATE/SUMMARY.md"
cat "results/$DATE/SUMMARY.md"

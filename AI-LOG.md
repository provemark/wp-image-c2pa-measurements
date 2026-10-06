# AI log

What Claude Code produced in this repository, per session. Newest at the bottom.

## 2026-10-06 — The measurement, and this repository

- Model: Claude Opus 5.5, Claude Code CLI
- Asked: measure what WordPress image plugins and CDNs do to C2PA Content
  Credentials ("zet die meting op"; "doe ronde 2 inclusief stap 2": also the
  plugins that send images to their own service, and Jetpack's CDN); then
  "begin met de repository", so that the article's results can be repeated.
- Produced: `bin/` (fetch-fixtures, env, prepare, sideload, measure, run-all,
  summarize, cdn-jetpack), `.wp-env.json`, `composer.json`, `package.json`,
  `fixtures/SHA256SUMS`, `README.md`, this log; `results/2026-10-06/`.
- Measured: before this repository, the same measurement in a scratch setup
  (two rounds). Round one used WP-CLI's container, whose ImageMagick had no
  JPEG support, so WordPress fell back to GD; it did not take the path a
  browser upload takes and was discarded. Round two went through the web
  server, with Imagick. Two set-up faults were found and fixed on the way:
  WordPress's requests to itself did not arrive in wp-env (so background
  jobs never ran), and WP-Optimize's queue only runs on a later WP-Cron
  request. Jetpack's CDN was checked from three hosts, with a
  cache-busting query, pixel by pixel, and against `c2patool` 0.27.22 and
  0.28.1. The scripts in this repository then repeated everything from a
  clean wp-env. Their first full run was wrong and was redone: WP-Cron was
  called with `?doing_wp_cron=`, which WordPress honours only when it matches
  its own lock, so no scheduled job ran; and EWWW and reSmush.it write their
  default settings on the first visit to wp-admin, which WP-CLI never makes.
  `bin/measure.sh` now calls WP-Cron without the parameter and opens wp-admin
  as the administrator after activating a plugin (wp-env's default test
  login). WP-Optimize then still compressed nothing: it schedules its queue
  five minutes after the upload (`time() + 300`), so its wait is now six
  minutes. After that the results match the scratch measurement.
- Decided by Maurice: what to measure, including sending the public test
  images through Smush's, reSmush.it's and Jetpack's services; reporting the
  CDN finding as Automattic/jetpack#53217; this repository, local and private
  until he decides otherwise.

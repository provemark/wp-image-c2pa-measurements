# What WordPress image tools do to Content Credentials

A signed image goes into WordPress. What does a visitor get? These scripts
measure it: for WordPress itself, for image plugins with their default
settings, and for Jetpack's image CDN. Every file WordPress and the plugin
write is checked for C2PA Content Credentials, and so is every image URL the
page hands a visitor, fetched the way a browser asks for it.

The write-up is the article
[What WordPress image plugins do to Content Credentials](https://provemark.github.io/articles/image-plugins-and-content-credentials/).
The results behind it are in [`results/`](results/), one folder per day.

## What is measured

| configuration | how it runs |
|---|---|
| WordPress only | as installed |
| Modern Image Formats (`webp-uploads`) | defaults |
| Converter for Media (`webp-converter-for-media`) | defaults |
| WebP Express (`webp-express`) | defaults |
| EWWW Image Optimizer (`ewww-image-optimizer`) | defaults |
| Smush (`wp-smushit`) | defaults; compresses through Smush's service |
| WP-Optimize (`wp-optimize`) | compression turned on (it is off by default); compresses through reSmush.it |
| reSmush.it (`resmushit-image-optimizer`) | "optimize on upload" set, as the first visit to wp-admin sets it |
| Jetpack image CDN (`i0.wp.com`) | public image URLs, no WordPress needed |

Three signed images: a small JPEG, a large JPEG signed by Lightroom
(3280×2451, so WordPress makes a `-scaled` copy), and a PNG generated and
signed by OpenAI. They are downloaded from a fixed commit of
[provemark/tracefern-image-check](https://github.com/provemark/tracefern-image-check/tree/2d40bcdbc8d831be17cffa4516a323e264cba16c/tests/Fixtures)
and checked against [`fixtures/SHA256SUMS`](fixtures/SHA256SUMS); their
sources and licences are listed in that repository's `tests/Fixtures/README.md`.

Each image is uploaded the way the browser does it (`media_handle_sideload`
in the web server, with Imagick), WP-Cron is kept running for a while so
background jobs finish, and then:

- `files.txt`: every image file written under `wp-content/` since the upload;
- `served.txt`: every URL in the image tag's `src` and `srcset`, fetched with
  `Accept: image/avif,image/webp`, as Chrome sends it;
- `config.txt`: date, WordPress, PHP, plugin version, image editor.

Each file is checked with [c2pa-verifier](https://github.com/provemark/c2pa-verifier),
which gives `c2patool`'s verdicts. `signingCredential.untrusted` and
`.expired` are left out of the failure column: no trust list is used, so
every test signature is untrusted.

## Run it

You need Docker, Node.js, PHP 8.3 and Composer.

```sh
composer install
npm install
bin/fetch-fixtures.sh
npx wp-env start
bin/prepare.sh        # local image tools, and a loopback for WP-Cron
bin/run-all.sh        # about half an hour; writes results/<date>/
bin/cdn-jetpack.sh    # a minute; writes results/<date>/jetpack-cdn.txt
```

One configuration and one image: `bin/measure.sh <out-dir> <image> [plugin[@version]]`.

`bin/prepare.sh` changes the web-server container: it installs the local
tools image plugins look for (jpegtran, optipng, pngquant, gifsicle, cwebp)
and forwards the site's port inside the container, so that WordPress's
requests to itself arrive. Without the forward, background jobs never run in
wp-env. Rebuilding the containers undoes both.

## Text

Text can carry Content Credentials too (C2PA 2.4 §A.8): the manifest is
appended as invisible Unicode variation selectors. `bin/text-measure.sh`
saves two signed texts as posts over the REST API, as an administrator and as
an author (whose content WordPress filters), in classic form and in a
paragraph block, and uploads them as `.txt` files. It checks what is stored,
what the API renders, whether the page carries that rendered content byte for
byte, and the uploaded file. The signed texts are in `text-fixtures/`, made
with the public c2patool test certificate.

The stock `c2patool` does not read text yet; text support in `c2pa-rs` is
behind the experimental `unstable_plain_text` feature. Build `c2patool` 0.28.1
with `unstable_plain_text` added to its `c2pa` features and pass it as
`TEXT_C2PATOOL`:

```sh
TEXT_C2PATOOL=/path/to/c2patool bin/text-measure.sh results/<date>-text
```

## Limits

- **Defaults.** Other settings give other results. A setting that keeps
  "metadata" usually means EXIF and XMP, not C2PA.
- **Not measured:** plugins that need an account (Imagify, ShortPixel,
  Optimole, TinyPNG, LiteSpeed, Image Optimizer).
- **EWWW on arm64.** EWWW ships its compression tools for x86; on an arm64
  machine its own compression step does not run, only its resizing. The
  workflow `Measure on x86` (`.github/workflows/x86.yml`, started by hand)
  measures WordPress and EWWW on GitHub's x86 runners, with EWWW's own record
  of each file in `after.txt`.
- **Three images.** Enough to show what happens, not to give percentages.
- **A date.** Plugins change. Each results folder is what happened that day,
  with those versions.

## How this was made

The scripts and the measurements were made with Claude Code; `AI-LOG.md`
records what was asked and what was produced. Every result in `results/` was
produced by running these scripts, not written by hand.

## Licence

MIT, for the scripts. The test images are not part of this repository.

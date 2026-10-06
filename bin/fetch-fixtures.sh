#!/bin/bash
# Downloads the signed test images from a fixed commit of the public
# provemark/tracefern-image-check repository and checks them against
# fixtures/SHA256SUMS. The images are not kept in this repository; see
# fixtures/README in that repository for their sources and licences.
set -eu
cd "$(dirname "$0")/../fixtures"
COMMIT=2d40bcdbc8d831be17cffa4516a323e264cba16c
BASE=https://raw.githubusercontent.com/provemark/tracefern-image-check/$COMMIT/tests/Fixtures
while read -r _ name; do
  [ -f "$name" ] || curl -fsSL -o "$name" "$BASE/$name"
done < SHA256SUMS
shasum -a 256 -c SHA256SUMS

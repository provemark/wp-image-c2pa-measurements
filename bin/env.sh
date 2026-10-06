# Sourced by the other scripts: the wp-env containers of this checkout.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PORT=8894
KEY=$(basename "$ROOT" | tr '[:upper:]' '[:lower:]')
CLI=$(docker ps --format '{{.Names}}' | grep -i "^wp-env-${KEY}-[0-9a-f]*-cli-1$" | head -1)
WEB=$(docker ps --format '{{.Names}}' | grep -i "^wp-env-${KEY}-[0-9a-f]*-wordpress-1$" | head -1)
if [ -z "$CLI" ] || [ -z "$WEB" ]; then
  echo "wp-env is not running for $ROOT (npm run env:start)" >&2
  exit 1
fi
VERIFY="php $ROOT/vendor/bin/c2pa-verify"

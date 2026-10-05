#!/usr/bin/env bash
# Runs the RealWorld API suite (Hurl) against a fresh build. Needs hurl 5 or newer (HURL=/path/to/hurl
# to pick one) and a checkout of realworld-apps/realworld (REALWORLD=/path/to/realworld, default
# ../realworld).
set -euo pipefail

cd "$(dirname "$0")/.."
REALWORLD="${REALWORLD:-../realworld}"
export PORT="${PORT:-8000}"

scripts/with-server.sh "${HURL:-hurl}" --test --jobs 1 \
  --variable "host=http://localhost:$PORT" \
  --variable "uid=$(date +%s)$$" \
  "$REALWORLD"/specs/api/hurl/*.hurl

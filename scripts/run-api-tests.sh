#!/usr/bin/env bash
# Builds the server, starts it against $DATABASE_URL, and runs the RealWorld Hurl suite against it.
# Needs hurl 5 or newer (HURL=/path/to/hurl to pick one) and a checkout of realworld-apps/realworld
# (REALWORLD=/path/to/realworld, default ../realworld).
set -euo pipefail

cd "$(dirname "$0")/.."
REALWORLD="${REALWORLD:-../realworld}"
HURL="${HURL:-hurl}"
PORT="${PORT:-8000}"
export DATABASE_URL="${DATABASE_URL:-dbname=realworld}"
export JWT_SECRET="${JWT_SECRET:-api-tests-secret-that-is-at-least-32-bytes}"
export PORT

lake build realworld
./.lake/build/bin/realworld &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT

for _ in $(seq 50); do
  curl -sf "http://localhost:$PORT/api/tags" >/dev/null && break
  sleep 0.1
done

"$HURL" --test --jobs 1 \
  --variable "host=http://localhost:$PORT" \
  --variable "uid=$(date +%s)$$" \
  "$REALWORLD"/specs/api/hurl/*.hurl

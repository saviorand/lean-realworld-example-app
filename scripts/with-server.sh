#!/usr/bin/env bash
# Builds the server, starts it against $DATABASE_URL on $PORT, runs the command it is given, and
# stops the server when that command exits.
set -euo pipefail

cd "$(dirname "$0")/.."
export PORT="${PORT:-8000}"
export DATABASE_URL="${DATABASE_URL:-dbname=realworld}"
export JWT_SECRET="${JWT_SECRET:-test-secret-that-is-at-least-32-bytes-long}"

lake build realworld
# lean-libcrypto builds its OpenSSL shim as a shared library, which Linux has to be told where to
# find; macOS records its path in the binary.
export LD_LIBRARY_PATH="$PWD/.lake/packages/libcrypto/.lake/build/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
./.lake/build/bin/realworld &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT

for _ in $(seq 50); do
  curl -sf "http://localhost:$PORT/api/tags" >/dev/null && break
  sleep 0.1
done

"$@"

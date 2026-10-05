#!/usr/bin/env bash
# Runs the RealWorld frontend suite (Playwright) against a fresh build, in the suite's `fullstack`
# mode. Needs `npm ci && npx playwright install chromium` in e2e/, a checkout of
# realworld-apps/realworld (REALWORLD=/path/to/realworld, default ../realworld), and a database
# with no articles yet, since the tests look for the tags they create among the popular ones.
set -euo pipefail

cd "$(dirname "$0")/.."
REALWORLD="${REALWORLD:-../realworld}"

# Copied in rather than referred to, so that the specs' imports resolve to e2e/node_modules.
rm -rf e2e/specs
cp -R "$REALWORLD/specs/e2e" e2e/specs

scripts/with-server.sh sh -c 'cd e2e && TEST_MODE=fullstack npx playwright test'

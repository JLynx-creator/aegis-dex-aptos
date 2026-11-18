#!/usr/bin/env bash
# Clean build + full unit-test run. Requires: aptos CLI (>= 9.x), git, network access to github.com.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build testnet_tokens/build
aptos move compile --dev
aptos move test                       # authoritative pass/fail (dev-address aegis=0xcafe)
# Coverage is informational: `test --coverage` prints a harmless unresolved-address error at the end
# on some CLI versions, so its exit code is ignored and the summary is read separately.
aptos move test --coverage >/dev/null 2>&1 || true
aptos move coverage summary --dev || true
(cd testnet_tokens && aptos move compile --dev)

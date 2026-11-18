#!/usr/bin/env bash
# Reproducible TESTNET deployment: test tokens + Aegis. Requires: aptos CLI, jq.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f config/testnet.env ] && source config/testnet.env
PROFILE="${PROFILE:-aegis-testnet}"
NETWORK="${NETWORK:-testnet}"
[ "$NETWORK" = "testnet" ] || { echo "refusing: this script is for testnet only"; exit 1; }

if ! aptos config show-profiles --profile "$PROFILE" >/dev/null 2>&1; then
  aptos init --profile "$PROFILE" --network "$NETWORK" --assume-yes
fi
ADDR=$(aptos config show-profiles --profile "$PROFILE" | jq -r '.Result[].account' | head -n1)
echo "Deployer: 0x${ADDR#0x}"
aptos account fund-with-faucet --profile "$PROFILE" || echo "Faucet failed: fund the account via the web faucet and re-run."

./scripts/test.sh

(cd testnet_tokens && aptos move publish --profile "$PROFILE" --named-addresses aegis_test="$PROFILE" --assume-yes)
aptos move publish --profile "$PROFILE" --named-addresses aegis="$PROFILE" --assume-yes
echo "Deployed. Run ./scripts/smoke_testnet.sh"

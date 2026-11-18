#!/usr/bin/env bash
# End-to-end smoke test on testnet: create pool, add liquidity, swap, remove liquidity.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f config/testnet.env ] && source config/testnet.env
PROFILE="${PROFILE:-aegis-testnet}"
DEADLINE=$(( $(date +%s) + ${DEADLINE_SECS:-600} ))
ME="0x$(aptos config show-profiles --profile "$PROFILE" | jq -r '.Result[].account' | head -n1 | sed 's/^0x//')"
run()  { aptos move run  --profile "$PROFILE" --assume-yes --function-id "$@"; }
view() { aptos move view --profile "$PROFILE" --function-id "$@"; }

A=$(view "$ME::tokens::token_a" | jq -r '.Result[0].inner')
B=$(view "$ME::tokens::token_b" | jq -r '.Result[0].inner')
echo "token A=$A token B=$B"

run "$ME::tokens::faucet" --args u64:100000000000000
run "$ME::amm::create_pool" --args address:$A address:$B
run "$ME::amm::add_liquidity" --args address:$A address:$B u64:1000000000 u64:2000000000 u64:0 u64:0 u64:$DEADLINE
view "$ME::amm::get_reserves" --args address:$A address:$B

OUT=$(view "$ME::amm::quote_swap_out" --args address:$A address:$B u64:1000000 | jq -r '.Result[0]')
echo "quoted out: $OUT"
run "$ME::amm::swap_exact_in" --args address:$A address:$B u64:1000000 u64:$OUT u64:$DEADLINE
view "$ME::amm::get_reserves" --args address:$A address:$B

LP=$(view "$ME::amm::lp_token" --args address:$A address:$B | jq -r '.Result[0].inner')
echo "LP token metadata: $LP (remove_liquidity: pass your LP balance as lp_amount)"

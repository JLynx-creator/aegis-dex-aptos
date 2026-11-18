# Known limitations and security assumptions

## Status
Unaudited. 48 tests pass (~87 % line coverage), including randomized multi-user sequences that check after every
step: pool balances == tracked reserves, LP supply == sum of holders, tokens conserved, k never decreases on swaps,
locked minimum intact; plus add/remove and swap round trips never profit. A one-off run of 60 extra seeds x 80 steps
found no violation.
Not done: independent audit, Move Prover specs (prover dependencies could not be installed in the authoring
environment), coverage-guided fuzzing, economic/MEV review, mainnet-fork testing.
**No claim of production security is made.**

## Security assumptions
1. Aptos VM, framework (`fungible_asset`, `primary_fungible_store`, `object`) and `timestamp` behave as documented.
2. Aptos Move forbids module re-entrancy at runtime; the per-pool `locked` flag and checks-effects-interactions
   ordering are defence in depth. This assumption must be re-verified by the auditor.
3. Listed tokens are honest, plain fungible assets: no freezing of the pool's store, no rebasing, no hooks that
   misreport amounts. Deposits revert if the pool does not receive exactly the requested amount.
4. The publisher key (or upgrade authority) is trusted until the package is made immutable (see DEPLOYMENT.md).

## Known limitations
- **Permissionless pools accept any token.** Anyone can create a pool for a malicious/worthless token. Front-ends
  must use an allowlist; the contract does not.
- **Donated tokens are stuck.** Reserves are tracked, so assets sent directly to a pool address are unrecoverable
  (no `skim`). This is the price of donation-attack resistance.
- **First-LP price setting.** The first depositor sets the initial price; arbitrageurs may take value if it is wrong.
  Create the pool and add liquidity in one transaction bundle and set sensible minimums.
- **Sandwich/MEV.** `min_amount_out` and `deadline` limit but do not eliminate sandwiching.
- **Issuer freeze / clawback** on a listed token can freeze pool funds or break withdrawals for that pool only.
- **No pause, no admin, no protocol fee, no oracle/TWAP, no multi-hop router, no flash swaps.**
- **No emergency recovery**: a discovered bug cannot be paused; remediation depends on the upgrade policy.
- **u64 limits.** Reserves above 2^64−1 abort; 8-decimal tokens with very large supplies may hit this.
- **Dust.** Rounding dust (always in favour of the pool) stays in reserves; 1000 LP units are permanently locked.
- **`init_module` assumption.** Factory address derives from `@aegis`; init asserts the signer equals `@aegis`.
  Verify this on testnet with the exact deployment method planned for mainnet.
- Gas costs and event-indexing behaviour have not been benchmarked.

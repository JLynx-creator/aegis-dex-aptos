# Deployment

## Testnet (reproducible)
Prereqs: Aptos CLI >= 9.x, `jq`, git.
```
cp config/testnet.env.example config/testnet.env   # optional
./scripts/deploy_testnet.sh      # init profile, faucet, test, publish tokens + aegis
./scripts/smoke_testnet.sh       # create pool, add liquidity, quote, swap
```
Note: these scripts were syntax-checked but **not executed against testnet** in the authoring environment.
Run them once and fix any CLI-flag differences for your CLI version.
Manual `remove_liquidity` check: read your LP balance, then
`aptos move run --function-id <addr>::amm::remove_liquidity --args address:<A> address:<B> u64:<lp> u64:0 u64:0 u64:<deadline>`.

## Mainnet checklist
- [ ] Independent security audit completed; all high/medium findings fixed and re-reviewed
- [ ] Move Prover specs for k-invariant, supply/reserve consistency, no-negative-balance (recommended)
- [ ] Fuzz/property tests and a testnet soak with adversarial scripts
- [ ] Test deployment done with the *same method* as mainnet (publish vs `deploy-object`); `init_module` verified, factory address checked
- [ ] Decide upgrade policy: keep a multisig-controlled publisher with timelock, or make the package immutable
      (immutable removes the ability to fix bugs; pick consciously)
- [ ] Publisher key on hardware wallet / multisig; no single hot key
- [x] Framework dependency pinned to commit c7f8af62 in Move.toml (re-evaluate against the framework version live on mainnet at launch); [ ] pin the CLI version used for the release build
- [ ] Verify published bytecode matches the audited commit (`aptos move verify-package`)
- [ ] Front-end token allowlist, price-impact warnings, default slippage and deadline
- [ ] Monitoring on events and reserve/balance divergence; incident-response plan
- [ ] Start with capped liquidity / guarded launch; publish limitations from SECURITY.md to users
- [ ] Do NOT publish `testnet_tokens` on mainnet

## Web app deployment
1. Publish the contract and note the publisher address; verify the token list (address + decimals) on an explorer.
2. Set `VITE_NETWORK`, `VITE_AEGIS_ADDRESS`, `VITE_TOKENS` at build time (values are baked into the bundle).
3. `make test-app` then deploy `app/dist` to static hosting.
4. Serve with HTTPS and security headers (CSP, `X-Content-Type-Options`, `Referrer-Policy`, HSTS). `index.html` ships a
   baseline CSP meta tag; prefer real response headers and tighten `connect-src` to your fullnode/indexer hosts.
5. Manually test on testnet with at least two wallets: connect, create pool, add, swap, remove, wrong-network banner,
   rejected signature, and a failing swap (tight slippage) to confirm error messages.

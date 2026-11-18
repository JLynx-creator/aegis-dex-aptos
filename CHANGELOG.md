# Changelog
All notable changes follow [Keep a Changelog](https://keepachangelog.com/) and semantic versioning.

## [0.1.0] - unreleased
### Added
- `aegis::amm` Move module: permissionless pools, exact-input swaps (0.30 % fee), add/remove liquidity,
  LP shares as a fungible asset, 1000-unit locked minimum liquidity, events and views.
- 48 Move tests (unit, negative, randomized invariant, no-free-lunch properties).
- `@aegis-dex/sdk` TypeScript SDK (bigint math mirroring the contract, payload builders, error mapping), 22 tests.
- React web app (swap, liquidity, token allowlist, slippage and price-impact guards), 6 tests.
- Testnet token package, deployment scripts, CI workflow, documentation.
### Known gaps
- Not audited. See docs/SECURITY.md before any mainnet use.

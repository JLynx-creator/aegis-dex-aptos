# Aegis — constant-product AMM on Aptos

Non-custodial x·y=k DEX written in Move: permissionless pools, exact-input swaps with slippage and deadline
protection, a 0.30 % fee that accrues to liquidity providers, LP shares as a standard Aptos fungible asset.
Includes a TypeScript SDK and a React web app.

> **Status: unaudited.** Passing tests is not a security proof. Do not use real funds on mainnet before an
> independent audit. See [SECURITY.md](SECURITY.md) and [docs/SECURITY.md](docs/SECURITY.md).

## Repository layout
| Path | What |
|---|---|
| `sources/amm.move` | The whole protocol (single module, no admin) |
| `tests/` | 48 Move tests: unit/negative, randomized invariants, no-free-lunch properties |
| `testnet_tokens/` | Two freely mintable test tokens (**testnet only**) |
| `sdk/` | `@aegis-dex/sdk`: bigint math mirroring the contract, payload builders, error mapping (22 tests) |
| `app/` | React + Vite web app: swap, liquidity, allowlisted tokens, slippage/price-impact guards (6 tests) |
| `scripts/` | `test.sh`, `deploy_testnet.sh`, `smoke_testnet.sh` |
| `docs/` | ARCHITECTURE, SECURITY (limitations + assumptions), DEPLOYMENT (testnet + mainnet checklist) |
| `.github/` | CI workflow, Dependabot |

## Quick start
Requirements: Aptos CLI 9.6.x, Node 22, git, internet access.
```bash
make test        # Move tests + SDK tests/build + app tests/build
```
Individual targets: `make test-move`, `make test-sdk`, `make test-app`. A `Dockerfile` provides the same toolchain.

## Contract entry points
| Function | Purpose |
|---|---|
| `create_pool(creator, a, b)` | permissionless; one pool per unordered pair |
| `add_liquidity(user, a, b, a_desired, b_desired, a_min, b_min, deadline)` | takes ratio-matched amounts only |
| `remove_liquidity(user, a, b, lp_amount, a_min, b_min, deadline)` | burns the caller's own LP |
| `swap_exact_in(user, in, out, amount_in, min_out, deadline)` | 0.30 % fee, k never decreases |
| views | `pool_address`, `pool_exists`, `get_reserves`, `lp_total_supply`, `lp_token`, `quote_swap_out` |

Abort codes are at the top of `sources/amm.move` and mirrored in `sdk/src/errors.ts`.

## SDK
```ts
import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";
import { AegisClient } from "@aegis-dex/sdk";

const aptos = new Aptos(new AptosConfig({ network: Network.TESTNET }));
const aegis = new AegisClient(aptos, "0x<publisher>");
const pool = await aegis.getPool(tokenA, tokenB);
const { payload, minOut } = aegis.swapExactIn(tokenA, tokenB, 1_000_000n, pool.reserveA, pool.reserveB, { slippageBps: 50 });
// sign and submit `payload` with your wallet / account
```
The SDK only builds payloads and reads state. Its math is tested against the same vectors as the Move tests.

## Web app
```bash
cd sdk && npm ci && npm run build          # the app consumes the SDK via file:../sdk
cd ../app && npm ci
cp .env.example .env                       # set VITE_NETWORK, VITE_AEGIS_ADDRESS, VITE_TOKENS (allowlist)
npm run dev                                # or: npm run build && npm run preview
```
Only tokens in `VITE_TOKENS` can be selected. The app was type-checked, unit-tested and production-built, but
**not exercised against a real wallet or live chain**; do that on testnet before any release.

## Releases and process
See [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md), [LICENSE](LICENSE) (MIT, change if needed).

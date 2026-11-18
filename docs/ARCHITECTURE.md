# Architecture

## Objects
```
@aegis (publisher / code)
  └─ Factory object  (named object "AEGIS_FACTORY_V1", non-transferable; holds an ExtendRef)
       └─ Pool object (named object, seed = bcs(token0) ++ bcs(token1), token0 < token1)
            ├─ Pool resource: token0, token1, reserve0, reserve1, MintRef, BurnRef, ExtendRef, locked
            ├─ LP fungible-asset metadata (the pool object IS the LP token metadata)
            ├─ primary store of token0 (owned by pool address)
            └─ primary store of token1 (owned by pool address)
```
- Pool address is deterministic from the *sorted* pair, so (A,B) and (B,A) map to the same pool and a
  duplicate pool cannot exist.
- Only this module can obtain the pool signer (via the stored ExtendRef), so reserves can only leave the
  pool through `remove_liquidity` or `swap_exact_in`. There is no admin or owner function.
- Pool and factory objects have ungated transfer disabled.

## Math
- Swap: `out = in·997·r_out / (r_in·1000 + in·997)` (u256 intermediate, floor). The 0.30 % fee stays in
  the pool, so k grows on every swap and LPs earn fees through reserve growth. After computing, the code
  re-checks `new_in · new_out >= old_in · old_out`.
- First deposit: `total = floor(sqrt(a0·a1))`, must be `> 1000`. `1000` LP units are minted to the pool
  address itself and never burnable (permanent lock); provider receives `total − 1000`.
- Later deposits: pool takes ratio-matched amounts (`opt = a·r_b/r_a`, floor); LP = `min(a0·S/r0, a1·S/r1)`
  (floor). Rounding always favours existing LPs.
- Withdrawal: `out_i = lp·r_i/S` (floor); both outputs must be > 0 and meet the caller's minimums. The
  locked minimum guarantees reserves never reach zero once a pool is initialised.
- All reserves are u64 (the FA balance type); additions use checked u128 arithmetic and abort on overflow.

## State-safety pattern
Every mutating function: validate inputs → compute → set `locked` → update reserves (effects) → move funds
(interactions) → emit event → clear `locked`. Any abort reverts the whole transaction, so there is no
partial state. Deposits verify the pool balance increased by exactly the requested amount, which rejects
fee-on-transfer style tokens.
- Reserves are tracked variables, not raw balances, so direct donations cannot change price or share value.

## Events
`PoolCreated`, `LiquidityAdded`, `LiquidityRemoved`, `Swapped`.

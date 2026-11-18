/// Aegis: a non-custodial constant-product (x * y = k) AMM on Aptos.
///
/// Design summary (see docs/ARCHITECTURE.md for details):
///  * One pool per unordered pair of fungible-asset metadata objects.
///  * Each pool is a non-transferable named object owned by a factory object. The pool object
///    doubles as the metadata object of its LP token (an Aptos fungible asset).
///  * Reserves are tracked in storage (`reserve0`/`reserve1`), never read from raw balances, so
///    tokens donated directly to the pool cannot move the price or inflate LP share value.
///  * No admin, no privileged withdrawal path, no protocol fee: the 0.30% fee stays in the pool
///    and accrues to LPs through reserve growth.
///  * Every state-changing function: checks inputs -> computes -> updates storage -> moves funds
///    (checks-effects-interactions) and holds a per-pool lock for its whole duration.
module aegis::amm {
    use std::bcs;
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_std::math128;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, BurnRef};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    // ------------------------------------------------------------------ errors
    const E_IDENTICAL_TOKENS: u64 = 1;
    const E_POOL_EXISTS: u64 = 2;
    const E_POOL_NOT_FOUND: u64 = 3;
    const E_ZERO_AMOUNT: u64 = 4;
    const E_EXPIRED: u64 = 5;
    const E_INSUFFICIENT_OUTPUT: u64 = 6;
    const E_INSUFFICIENT_AMOUNT_MIN: u64 = 7;
    const E_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 8;
    const E_INSUFFICIENT_LIQUIDITY_BURNED: u64 = 9;
    const E_LOCKED: u64 = 10;
    const E_RESERVE_OVERFLOW: u64 = 11;
    const E_UNEXPECTED_TRANSFER_AMOUNT: u64 = 12;
    const E_INVALID_STATE: u64 = 13;
    const E_NOT_DEPLOYER: u64 = 14;
    const E_INSUFFICIENT_INITIAL_LIQUIDITY: u64 = 15;
    const E_K_INVARIANT: u64 = 16;
    const E_INSUFFICIENT_RESERVES: u64 = 17;

    // --------------------------------------------------------------- constants
    /// Swap fee = 1 - 997/1000 = 0.30%.
    const FEE_NUMERATOR: u256 = 997;
    const FEE_DENOMINATOR: u256 = 1000;
    /// LP units permanently locked in the pool on first deposit (anti share-inflation).
    const MINIMUM_LIQUIDITY: u64 = 1000;
    const MAX_U64: u128 = 18446744073709551615;
    const LP_DECIMALS: u8 = 8;
    const FACTORY_SEED: vector<u8> = b"AEGIS_FACTORY_V1";

    // ----------------------------------------------------------------- storage
    /// Stored at the factory object's address. Lets the module sign for pool creation.
    struct Factory has key {
        extend_ref: ExtendRef
    }

    /// Stored at the pool object's address (which is also the LP token metadata address).
    struct Pool has key {
        token0: Object<Metadata>,
        token1: Object<Metadata>,
        reserve0: u64,
        reserve1: u64,
        lp_mint_ref: MintRef,
        lp_burn_ref: BurnRef,
        extend_ref: ExtendRef,
        locked: bool
    }

    // ------------------------------------------------------------------ events
    #[event]
    struct PoolCreated has drop, store {
        pool: address,
        token0: address,
        token1: address
    }

    #[event]
    struct LiquidityAdded has drop, store {
        pool: address,
        provider: address,
        amount0: u64,
        amount1: u64,
        lp_minted: u64
    }

    #[event]
    struct LiquidityRemoved has drop, store {
        pool: address,
        provider: address,
        amount0: u64,
        amount1: u64,
        lp_burned: u64
    }

    #[event]
    struct Swapped has drop, store {
        pool: address,
        trader: address,
        token_in: address,
        token_out: address,
        amount_in: u64,
        amount_out: u64
    }

    // -------------------------------------------------------------------- init
    fun init_module(deployer: &signer) {
        assert!(signer::address_of(deployer) == @aegis, E_NOT_DEPLOYER);
        let cref = object::create_named_object(deployer, FACTORY_SEED);
        let factory_signer = object::generate_signer(&cref);
        let transfer_ref = object::generate_transfer_ref(&cref);
        object::disable_ungated_transfer(&transfer_ref);
        move_to(&factory_signer, Factory { extend_ref: object::generate_extend_ref(&cref) });
    }

    #[test_only]
    public fun init_for_test(deployer: &signer) {
        init_module(deployer);
    }

    // ------------------------------------------------------------ pool creation
    /// Permissionless. Creates an empty pool for the pair. Order of arguments does not matter.
    public entry fun create_pool(
        _creator: &signer, token_a: Object<Metadata>, token_b: Object<Metadata>
    ) acquires Factory {
        let (token0, token1) = sort_tokens(token_a, token_b);
        let seed = pool_seed(token0, token1);
        let factory_addr = factory_address();
        let pool_addr = object::create_object_address(&factory_addr, seed);
        assert!(!exists<Pool>(pool_addr), E_POOL_EXISTS);

        let factory_signer =
            object::generate_signer_for_extending(
                &borrow_global<Factory>(factory_addr).extend_ref
            );
        let cref = object::create_named_object(&factory_signer, seed);
        let pool_signer = object::generate_signer(&cref);

        // LP token: the pool object itself is the fungible-asset metadata object.
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &cref,
            option::none(),
            string::utf8(b"Aegis LP"),
            string::utf8(b"AEGIS-LP"),
            LP_DECIMALS,
            string::utf8(b""),
            string::utf8(b"")
        );

        // The pool must never be transferable.
        let transfer_ref = object::generate_transfer_ref(&cref);
        object::disable_ungated_transfer(&transfer_ref);

        // Reserve stores are owned by the pool address; only this module can sign for it.
        primary_fungible_store::ensure_primary_store_exists(pool_addr, token0);
        primary_fungible_store::ensure_primary_store_exists(pool_addr, token1);

        move_to(
            &pool_signer,
            Pool {
                token0,
                token1,
                reserve0: 0,
                reserve1: 0,
                lp_mint_ref: fungible_asset::generate_mint_ref(&cref),
                lp_burn_ref: fungible_asset::generate_burn_ref(&cref),
                extend_ref: object::generate_extend_ref(&cref),
                locked: false
            }
        );

        event::emit(
            PoolCreated {
                pool: pool_addr,
                token0: object::object_address(&token0),
                token1: object::object_address(&token1)
            }
        );
    }

    // ------------------------------------------------------- add liquidity
    /// Deposit up to `amount_a_desired` / `amount_b_desired`. The pool takes the best ratio-matching
    /// amounts (never more than desired); the rest never leaves the caller's wallet.
    /// Aborts if the taken amounts are below the given minimums or `deadline` (unix secs) passed.
    public entry fun add_liquidity(
        user: &signer,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        deadline: u64
    ) acquires Pool {
        assert!(timestamp::now_seconds() <= deadline, E_EXPIRED);
        assert!(amount_a_desired > 0 && amount_b_desired > 0, E_ZERO_AMOUNT);

        let (token0, token1) = sort_tokens(token_a, token_b);
        let a_is_0 = object::object_address(&token_a) == object::object_address(&token0);
        let (d0, d1, m0, m1) =
            if (a_is_0) {
                (amount_a_desired, amount_b_desired, amount_a_min, amount_b_min)
            } else {
                (amount_b_desired, amount_a_desired, amount_b_min, amount_a_min)
            };

        let pool_addr = pool_address_sorted(token0, token1);
        assert!(exists<Pool>(pool_addr), E_POOL_NOT_FOUND);
        let pool = borrow_global_mut<Pool>(pool_addr);
        assert!(!pool.locked, E_LOCKED);
        pool.locked = true;

        let lp_metadata = object::address_to_object<Metadata>(pool_addr);
        let supply = lp_supply_of(lp_metadata);
        let r0 = pool.reserve0;
        let r1 = pool.reserve1;

        // ---- choose amounts
        let (a0, a1) =
            if (supply == 0) {
                assert!(r0 == 0 && r1 == 0, E_INVALID_STATE);
                (d0, d1)
            } else {
                assert!(r0 > 0 && r1 > 0, E_INVALID_STATE);
                let opt1 = quote(d0, r0, r1);
                if (opt1 <= d1) {
                    (d0, opt1)
                } else {
                    let opt0 = quote(d1, r1, r0);
                    assert!(opt0 <= d0, E_INVALID_STATE);
                    (opt0, d1)
                }
            };
        assert!(a0 >= m0 && a1 >= m1, E_INSUFFICIENT_AMOUNT_MIN);
        assert!(a0 > 0 && a1 > 0, E_ZERO_AMOUNT);

        // ---- compute LP shares (rounded down => in favour of existing LPs)
        let liquidity: u64;
        let locked_min: u64 = 0;
        if (supply == 0) {
            let root = math128::sqrt((a0 as u128) * (a1 as u128));
            assert!(root > (MINIMUM_LIQUIDITY as u128), E_INSUFFICIENT_INITIAL_LIQUIDITY);
            locked_min = MINIMUM_LIQUIDITY;
            liquidity = ((root - (MINIMUM_LIQUIDITY as u128)) as u64);
        } else {
            let l0 = ((a0 as u256) * (supply as u256)) / (r0 as u256);
            let l1 = ((a1 as u256) * (supply as u256)) / (r1 as u256);
            let l = if (l0 < l1) l0 else l1;
            assert!(l <= (MAX_U64 as u256), E_RESERVE_OVERFLOW);
            liquidity = (l as u64);
        };
        assert!(liquidity > 0, E_INSUFFICIENT_LIQUIDITY_MINTED);

        // ---- effects
        pool.reserve0 = checked_add(r0, a0);
        pool.reserve1 = checked_add(r1, a1);

        // ---- interactions
        pull(user, token0, pool_addr, a0);
        pull(user, token1, pool_addr, a1);
        if (locked_min > 0) {
            // Permanently locked: the pool address never calls burn on its own LP balance.
            primary_fungible_store::mint(&pool.lp_mint_ref, pool_addr, locked_min);
        };
        let provider = signer::address_of(user);
        primary_fungible_store::mint(&pool.lp_mint_ref, provider, liquidity);

        event::emit(
            LiquidityAdded { pool: pool_addr, provider, amount0: a0, amount1: a1, lp_minted: liquidity }
        );
        pool.locked = false;
    }

    // ---------------------------------------------------- remove liquidity
    /// Burn `lp_amount` of the caller's LP tokens for a proportional share of both reserves
    /// (rounded down). Aborts if either payout is below its minimum.
    public entry fun remove_liquidity(
        user: &signer,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        lp_amount: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        deadline: u64
    ) acquires Pool {
        assert!(timestamp::now_seconds() <= deadline, E_EXPIRED);
        assert!(lp_amount > 0, E_ZERO_AMOUNT);

        let (token0, token1) = sort_tokens(token_a, token_b);
        let a_is_0 = object::object_address(&token_a) == object::object_address(&token0);
        let (m0, m1) = if (a_is_0) (amount_a_min, amount_b_min) else (amount_b_min, amount_a_min);

        let pool_addr = pool_address_sorted(token0, token1);
        assert!(exists<Pool>(pool_addr), E_POOL_NOT_FOUND);
        let pool = borrow_global_mut<Pool>(pool_addr);
        assert!(!pool.locked, E_LOCKED);
        pool.locked = true;

        let lp_metadata = object::address_to_object<Metadata>(pool_addr);
        let supply = lp_supply_of(lp_metadata);
        assert!(supply > 0 && (lp_amount as u128) <= supply, E_INVALID_STATE);
        let r0 = pool.reserve0;
        let r1 = pool.reserve1;

        let out0 = (((lp_amount as u256) * (r0 as u256)) / (supply as u256) as u64);
        let out1 = (((lp_amount as u256) * (r1 as u256)) / (supply as u256) as u64);
        assert!(out0 > 0 && out1 > 0, E_INSUFFICIENT_LIQUIDITY_BURNED);
        assert!(out0 >= m0 && out1 >= m1, E_INSUFFICIENT_AMOUNT_MIN);
        assert!(out0 < r0 && out1 < r1, E_INSUFFICIENT_RESERVES); // locked minimum guarantees this

        // ---- effects
        pool.reserve0 = r0 - out0;
        pool.reserve1 = r1 - out1;

        // ---- interactions: burn only what the signer itself owns, then pay out
        let lp_fa = primary_fungible_store::withdraw(user, lp_metadata, lp_amount);
        fungible_asset::burn(&pool.lp_burn_ref, lp_fa);
        let provider = signer::address_of(user);
        let pool_signer = object::generate_signer_for_extending(&pool.extend_ref);
        push(&pool_signer, token0, provider, out0);
        push(&pool_signer, token1, provider, out1);

        event::emit(
            LiquidityRemoved { pool: pool_addr, provider, amount0: out0, amount1: out1, lp_burned: lp_amount }
        );
        pool.locked = false;
    }

    // ------------------------------------------------------------------ swap
    /// Exact-input swap. Aborts if output < `min_amount_out` or `deadline` passed.
    public entry fun swap_exact_in(
        user: &signer,
        token_in: Object<Metadata>,
        token_out: Object<Metadata>,
        amount_in: u64,
        min_amount_out: u64,
        deadline: u64
    ) acquires Pool {
        assert!(timestamp::now_seconds() <= deadline, E_EXPIRED);
        assert!(amount_in > 0, E_ZERO_AMOUNT);

        let (token0, token1) = sort_tokens(token_in, token_out);
        let in_is_0 = object::object_address(&token_in) == object::object_address(&token0);

        let pool_addr = pool_address_sorted(token0, token1);
        assert!(exists<Pool>(pool_addr), E_POOL_NOT_FOUND);
        let pool = borrow_global_mut<Pool>(pool_addr);
        assert!(!pool.locked, E_LOCKED);
        pool.locked = true;

        let (r_in, r_out) =
            if (in_is_0) (pool.reserve0, pool.reserve1) else (pool.reserve1, pool.reserve0);
        let amount_out = get_amount_out(amount_in, r_in, r_out);
        assert!(amount_out > 0 && amount_out >= min_amount_out, E_INSUFFICIENT_OUTPUT);

        let new_r_in = checked_add(r_in, amount_in);
        let new_r_out = r_out - amount_out; // amount_out < r_out is guaranteed by get_amount_out
        // The fee guarantees k never decreases; verify it explicitly.
        assert!(
            (new_r_in as u256) * (new_r_out as u256) >= (r_in as u256) * (r_out as u256),
            E_K_INVARIANT
        );

        // ---- effects
        if (in_is_0) {
            pool.reserve0 = new_r_in;
            pool.reserve1 = new_r_out;
        } else {
            pool.reserve1 = new_r_in;
            pool.reserve0 = new_r_out;
        };

        // ---- interactions
        pull(user, token_in, pool_addr, amount_in);
        let pool_signer = object::generate_signer_for_extending(&pool.extend_ref);
        let trader = signer::address_of(user);
        push(&pool_signer, token_out, trader, amount_out);

        event::emit(
            Swapped {
                pool: pool_addr,
                trader,
                token_in: object::object_address(&token_in),
                token_out: object::object_address(&token_out),
                amount_in,
                amount_out
            }
        );
        pool.locked = false;
    }

    // ---------------------------------------------------------------- math
    /// out = in * 997 * r_out / (r_in * 1000 + in * 997), rounded down (in favour of the pool).
    public fun get_amount_out(amount_in: u64, reserve_in: u64, reserve_out: u64): u64 {
        assert!(amount_in > 0, E_ZERO_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, E_INSUFFICIENT_RESERVES);
        let in_with_fee = (amount_in as u256) * FEE_NUMERATOR;
        let numerator = in_with_fee * (reserve_out as u256);
        let denominator = (reserve_in as u256) * FEE_DENOMINATOR + in_with_fee;
        ((numerator / denominator) as u64) // < reserve_out, so fits in u64
    }

    /// Proportional amount: a * reserve_b / reserve_a, rounded down.
    fun quote(amount_a: u64, reserve_a: u64, reserve_b: u64): u64 {
        assert!(amount_a > 0, E_ZERO_AMOUNT);
        assert!(reserve_a > 0 && reserve_b > 0, E_INSUFFICIENT_RESERVES);
        let r = ((amount_a as u256) * (reserve_b as u256)) / (reserve_a as u256);
        assert!(r <= (MAX_U64 as u256), E_RESERVE_OVERFLOW);
        (r as u64)
    }

    fun checked_add(a: u64, b: u64): u64 {
        let s = (a as u128) + (b as u128);
        assert!(s <= MAX_U64, E_RESERVE_OVERFLOW);
        (s as u64)
    }

    // ------------------------------------------------------ fund movement
    /// Move exactly `amount` from the user into the pool store, verifying the pool really
    /// received `amount` (rejects fee-on-transfer / hook tokens that short-change the pool).
    fun pull(user: &signer, token: Object<Metadata>, pool_addr: address, amount: u64) {
        let before = primary_fungible_store::balance(pool_addr, token);
        let fa = primary_fungible_store::withdraw(user, token, amount);
        assert!(fungible_asset::amount(&fa) == amount, E_UNEXPECTED_TRANSFER_AMOUNT);
        primary_fungible_store::deposit(pool_addr, fa);
        let after = primary_fungible_store::balance(pool_addr, token);
        assert!(after >= before && after - before == amount, E_UNEXPECTED_TRANSFER_AMOUNT);
    }

    fun push(pool_signer: &signer, token: Object<Metadata>, to: address, amount: u64) {
        let fa = primary_fungible_store::withdraw(pool_signer, token, amount);
        assert!(fungible_asset::amount(&fa) == amount, E_UNEXPECTED_TRANSFER_AMOUNT);
        primary_fungible_store::deposit(to, fa);
    }

    // ------------------------------------------------------------- helpers
    fun lp_supply_of(lp_metadata: Object<Metadata>): u128 {
        let s = fungible_asset::supply(lp_metadata);
        if (option::is_some(&s)) *option::borrow(&s) else 0
    }

    fun factory_address(): address {
        object::create_object_address(&@aegis, FACTORY_SEED)
    }

    fun pool_seed(token0: Object<Metadata>, token1: Object<Metadata>): vector<u8> {
        let seed = bcs::to_bytes(&object::object_address(&token0));
        vector::append(&mut seed, bcs::to_bytes(&object::object_address(&token1)));
        seed
    }

    fun pool_address_sorted(token0: Object<Metadata>, token1: Object<Metadata>): address {
        object::create_object_address(&factory_address(), pool_seed(token0, token1))
    }

    fun sort_tokens(
        a: Object<Metadata>, b: Object<Metadata>
    ): (Object<Metadata>, Object<Metadata>) {
        let aa = object::object_address(&a);
        let ba = object::object_address(&b);
        assert!(aa != ba, E_IDENTICAL_TOKENS);
        if (addr_lt(aa, ba)) (a, b) else (b, a)
    }

    fun addr_lt(a: address, b: address): bool {
        let x = bcs::to_bytes(&a);
        let y = bcs::to_bytes(&b);
        let i = 0;
        let n = vector::length(&x);
        while (i < n) {
            let xb = *vector::borrow(&x, i);
            let yb = *vector::borrow(&y, i);
            if (xb != yb) {
                return xb < yb
            };
            i = i + 1;
        };
        false
    }

    // --------------------------------------------------------------- views
    #[view]
    public fun pool_address(token_a: Object<Metadata>, token_b: Object<Metadata>): address {
        let (t0, t1) = sort_tokens(token_a, token_b);
        pool_address_sorted(t0, t1)
    }

    #[view]
    public fun pool_exists(token_a: Object<Metadata>, token_b: Object<Metadata>): bool {
        exists<Pool>(pool_address(token_a, token_b))
    }

    // Reserves are returned in the order (token_a, token_b) of the arguments.
    #[view]
    public fun get_reserves(
        token_a: Object<Metadata>, token_b: Object<Metadata>
    ): (u64, u64) acquires Pool {
        let addr = pool_address(token_a, token_b);
        assert!(exists<Pool>(addr), E_POOL_NOT_FOUND);
        let pool = borrow_global<Pool>(addr);
        if (object::object_address(&token_a) == object::object_address(&pool.token0)) {
            (pool.reserve0, pool.reserve1)
        } else {
            (pool.reserve1, pool.reserve0)
        }
    }

    #[view]
    public fun lp_total_supply(token_a: Object<Metadata>, token_b: Object<Metadata>): u128 {
        let addr = pool_address(token_a, token_b);
        assert!(exists<Pool>(addr), E_POOL_NOT_FOUND);
        lp_supply_of(object::address_to_object<Metadata>(addr))
    }

    #[view]
    public fun lp_token(
        token_a: Object<Metadata>, token_b: Object<Metadata>
    ): Object<Metadata> {
        let addr = pool_address(token_a, token_b);
        assert!(exists<Pool>(addr), E_POOL_NOT_FOUND);
        object::address_to_object<Metadata>(addr)
    }

    #[view]
    public fun quote_swap_out(
        token_in: Object<Metadata>, token_out: Object<Metadata>, amount_in: u64
    ): u64 acquires Pool {
        let (r_in, r_out) = get_reserves(token_in, token_out);
        get_amount_out(amount_in, r_in, r_out)
    }
}

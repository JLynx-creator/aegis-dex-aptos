#[test_only]
module aegis::invariant_tests {
    use std::vector;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aegis::amm;
    use aegis::test_helpers::{Self as th, bal};

    const DL: u64 = 2000;
    const FUND: u64 = 1_000_000_000_000_000;

    struct Rng has drop { s: u128 }

    fun next(r: &mut Rng, bound: u64): u64 {
        r.s = (r.s * 6364136223846793005 + 1442695040888963407) % 18446744073709551616;
        (((r.s >> 17) % (bound as u128)) as u64)
    }

    fun users(): vector<signer> {
        vector[th::signer_of(@0xA11CE), th::signer_of(@0xB0B), th::signer_of(@0xCA401)]
    }

    fun addr_at(i: u64): address {
        if (i == 0) @0xA11CE else if (i == 1) @0xB0B else @0xCA401
    }

    fun setup_pool(): (Object<Metadata>, Object<Metadata>) {
        th::setup();
        let creator = th::signer_of(@0xC0DE);
        let ta = th::create_token(&creator, b"TKA");
        let tb = th::create_token(&creator, b"TKB");
        let i = 0;
        while (i < 3) {
            th::mint(ta, addr_at(i), FUND);
            th::mint(tb, addr_at(i), FUND);
            i = i + 1;
        };
        let alice = th::signer_of(@0xA11CE);
        amm::create_pool(&alice, ta, tb);
        amm::add_liquidity(&alice, ta, tb, 2_000_000_000, 3_000_000_000, 0, 0, DL);
        (ta, tb)
    }

    fun check_invariants(ta: Object<Metadata>, tb: Object<Metadata>, total_a: u64, total_b: u64) {
        let pool = amm::pool_address(ta, tb);
        let (ra, rb) = amm::get_reserves(ta, tb);
        // INV1: real pool balances equal tracked reserves (no donations in this test)
        assert!(bal(pool, ta) == ra && bal(pool, tb) == rb, 900);
        // INV2: LP supply equals the sum of every holder's LP balance (3 users + locked share)
        let lp = amm::lp_token(ta, tb);
        let sum = (primary_fungible_store::balance(pool, lp) as u128);
        let i = 0;
        while (i < 3) {
            sum = sum + (primary_fungible_store::balance(addr_at(i), lp) as u128);
            i = i + 1;
        };
        assert!(sum == amm::lp_total_supply(ta, tb), 901);
        // INV3: locked minimum is intact and reserves are never empty
        assert!(primary_fungible_store::balance(pool, lp) == 1000, 902);
        assert!(ra > 0 && rb > 0, 903);
        // INV4: conservation of tokens across all participants + pool
        let sa = (ra as u128);
        let sb = (rb as u128);
        i = 0;
        while (i < 3) {
            sa = sa + (bal(addr_at(i), ta) as u128);
            sb = sb + (bal(addr_at(i), tb) as u128);
            i = i + 1;
        };
        assert!(sa == (total_a as u128) && sb == (total_b as u128), 904);
    }

    fun run_random(seed: u128, steps: u64) {
        let (ta, tb) = setup_pool();
        let us = users();
        let total_a = 3 * FUND;
        let total_b = 3 * FUND;
        let rng = Rng { s: seed };
        let step = 0;
        while (step < steps) {
            let who = next(&mut rng, 3);
            let u = vector::borrow(&us, who);
            let op = next(&mut rng, 10);
            let (ra, rb) = amm::get_reserves(ta, tb);
            if (op < 6) {
                // swap, up to 5% of the input reserve
                let a_to_b = next(&mut rng, 2) == 0;
                let (t_in, t_out, r_in) = if (a_to_b) (ta, tb, ra) else (tb, ta, rb);
                let amt = 10_000 + next(&mut rng, r_in / 20);
                let k0 = (ra as u256) * (rb as u256);
                amm::swap_exact_in(u, t_in, t_out, amt, 0, DL);
                let (na, nb) = amm::get_reserves(ta, tb);
                assert!((na as u256) * (nb as u256) >= k0, 910); // k never decreases on a swap
            } else if (op < 8) {
                let da = 1_000_000 + next(&mut rng, 100_000_000);
                let db = 1_000_000 + next(&mut rng, 100_000_000);
                amm::add_liquidity(u, ta, tb, da, db, 0, 0, DL);
            } else {
                let lp = amm::lp_token(ta, tb);
                let have = primary_fungible_store::balance(addr_at(who), lp);
                if (have > 100_000) {
                    let amt = 1 + next(&mut rng, have / 2);
                    amm::remove_liquidity(u, ta, tb, amt, 0, 0, DL);
                };
            };
            check_invariants(ta, tb, total_a, total_b);
            step = step + 1;
        };
        // Everyone exits: the pool must still hold the locked minimum, and nothing leaked.
        let i = 0;
        while (i < 3) {
            let lp = amm::lp_token(ta, tb);
            let have = primary_fungible_store::balance(addr_at(i), lp);
            if (have > 0) {
                amm::remove_liquidity(vector::borrow(&us, i), ta, tb, have, 0, 0, DL);
            };
            i = i + 1;
        };
        check_invariants(ta, tb, total_a, total_b);
        assert!(amm::lp_total_supply(ta, tb) == 1000, 920);
    }

    #[test] fun random_sequence_seed_1() { run_random(1, 60); }
    #[test] fun random_sequence_seed_2() { run_random(0xDEADBEEF, 60); }
    #[test] fun random_sequence_seed_3() { run_random(987654321987654321, 60); }
    #[test] fun random_sequence_seed_4() { run_random(42, 60); }
    #[test] fun random_sequence_seed_5() { run_random(0xFEEDFACECAFEBEEF, 60); }

    // ---------------------------------------------------- no-free-lunch properties
    #[test]
    fun swap_round_trip_never_profits() {
        let (ta, tb) = setup_pool();
        let bob = th::signer_of(@0xB0B);
        let amounts = vector[10_000u64, 777_777, 31_415_926, 200_000_000, 900_000_000];
        let i = 0;
        while (i < vector::length(&amounts)) {
            let amt = *vector::borrow(&amounts, i);
            let a_before = bal(@0xB0B, ta);
            let b_before = bal(@0xB0B, tb);
            amm::swap_exact_in(&bob, ta, tb, amt, 0, DL);
            let got_b = bal(@0xB0B, tb) - b_before;
            amm::swap_exact_in(&bob, tb, ta, got_b, 0, DL);
            assert!(bal(@0xB0B, ta) < a_before, 930); // strictly less: fee + rounding stay in the pool
            i = i + 1;
        };
    }

    #[test]
    fun add_then_remove_never_profits() {
        let (ta, tb) = setup_pool();
        let carol = th::signer_of(@0xCA401);
        let lp = amm::lp_token(ta, tb);
        let amounts = vector[1_000_000u64, 12_345_678, 400_000_000, 1_999_999_999];
        let i = 0;
        while (i < vector::length(&amounts)) {
            let d = *vector::borrow(&amounts, i);
            let a0 = bal(@0xCA401, ta);
            let b0 = bal(@0xCA401, tb);
            let lp0 = primary_fungible_store::balance(@0xCA401, lp);
            amm::add_liquidity(&carol, ta, tb, d, d * 2, 0, 0, DL);
            let minted = primary_fungible_store::balance(@0xCA401, lp) - lp0;
            amm::remove_liquidity(&carol, ta, tb, minted, 0, 0, DL);
            assert!(bal(@0xCA401, ta) <= a0 && bal(@0xCA401, tb) <= b0, 940);
            i = i + 1;
        };
    }

    #[test]
    fun lp_cannot_extract_more_than_pro_rata_share() {
        let (ta, tb) = setup_pool();
        let bob = th::signer_of(@0xB0B);
        let alice = th::signer_of(@0xA11CE);
        amm::add_liquidity(&bob, ta, tb, 500_000_000, 750_000_000, 0, 0, DL);
        let lp = amm::lp_token(ta, tb);
        let supply = amm::lp_total_supply(ta, tb);
        let (ra, rb) = amm::get_reserves(ta, tb);
        let bob_lp = primary_fungible_store::balance(@0xB0B, lp);
        let a0 = bal(@0xB0B, ta);
        let b0 = bal(@0xB0B, tb);
        amm::remove_liquidity(&bob, ta, tb, bob_lp, 0, 0, DL);
        let cap_a = (((bob_lp as u256) * (ra as u256) / (supply as u256)) as u64);
        let cap_b = (((bob_lp as u256) * (rb as u256) / (supply as u256)) as u64);
        assert!(bal(@0xB0B, ta) - a0 == cap_a && bal(@0xB0B, tb) - b0 == cap_b, 950);
        // Alice (the other LP) is unaffected by Bob's entry/exit beyond rounding dust in her favour.
        let alice_lp = primary_fungible_store::balance(@0xA11CE, lp);
        let s2 = amm::lp_total_supply(ta, tb);
        let (r2a, _) = amm::get_reserves(ta, tb);
        let alice_value_a = ((alice_lp as u256) * (r2a as u256) / (s2 as u256));
        assert!(alice_value_a >= 1_999_000_000 - 2_000, 951);
        let _ = alice;
    }
}

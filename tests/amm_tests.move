#[test_only]
module aegis::amm_tests {
    use std::signer;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aegis::amm;
    use aegis::test_helpers::{Self as th, bal};

    const DL: u64 = 2000; // deadline in the future (test clock starts at 1000)
    const E9: u64 = 1_000_000_000;

    // Error codes mirrored from aegis::amm
    // 1 identical, 2 exists, 3 no pool, 4 zero, 5 expired, 6 insufficient output,
    // 7 min amount, 8 lp minted 0, 9 lp burned 0, 11 overflow, 15 initial liquidity, 17 reserves

    fun fixture(): (signer, signer, Object<Metadata>, Object<Metadata>) {
        th::setup();
        let creator = th::signer_of(@0xC0DE);
        let ta = th::create_token(&creator, b"TKA");
        let tb = th::create_token(&creator, b"TKB");
        let alice = th::signer_of(@0xA11CE);
        let bob = th::signer_of(@0xB0B);
        th::mint(ta, @0xA11CE, 1_000_000_000_000);
        th::mint(tb, @0xA11CE, 1_000_000_000_000);
        th::mint(ta, @0xB0B, 1_000_000_000_000);
        th::mint(tb, @0xB0B, 1_000_000_000_000);
        (alice, bob, ta, tb)
    }

    fun pool_with(
        alice: &signer, ta: Object<Metadata>, tb: Object<Metadata>, a: u64, b: u64
    ) {
        amm::create_pool(alice, ta, tb);
        amm::add_liquidity(alice, ta, tb, a, b, 0, 0, DL);
    }

    fun k(ta: Object<Metadata>, tb: Object<Metadata>): u256 {
        let (x, y) = amm::get_reserves(ta, tb);
        (x as u256) * (y as u256)
    }

    // ------------------------------------------------------------ pool creation
    #[test]
    fun create_pool_is_order_independent() {
        let (alice, _bob, ta, tb) = fixture();
        assert!(!amm::pool_exists(ta, tb), 0);
        amm::create_pool(&alice, ta, tb);
        assert!(amm::pool_exists(ta, tb) && amm::pool_exists(tb, ta), 1);
        assert!(amm::pool_address(ta, tb) == amm::pool_address(tb, ta), 2);
        let (r0, r1) = amm::get_reserves(ta, tb);
        assert!(r0 == 0 && r1 == 0, 3);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = aegis::amm)]
    fun create_pool_identical_tokens_aborts() {
        let (alice, _bob, ta, _tb) = fixture();
        amm::create_pool(&alice, ta, ta);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = aegis::amm)]
    fun create_pool_duplicate_aborts_even_reversed() {
        let (alice, bob, ta, tb) = fixture();
        amm::create_pool(&alice, ta, tb);
        amm::create_pool(&bob, tb, ta);
    }

    // ------------------------------------------------------------ add liquidity
    #[test]
    fun first_deposit_issues_sqrt_minus_locked_minimum() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 4_000_000);
        let lp = amm::lp_token(ta, tb);
        // sqrt(1e6 * 4e6) = 2e6 total; 1000 locked in the pool, rest to the provider.
        assert!(amm::lp_total_supply(ta, tb) == 2_000_000, 0);
        assert!(primary_fungible_store::balance(@0xA11CE, lp) == 1_999_000, 1);
        assert!(primary_fungible_store::balance(amm::pool_address(ta, tb), lp) == 1_000, 2);
        let (r0, r1) = amm::get_reserves(ta, tb);
        assert!(r0 == 1_000_000 && r1 == 4_000_000, 3);
        assert!(bal(@0xA11CE, ta) == 1_000_000_000_000 - 1_000_000, 4);
        assert!(bal(@0xA11CE, tb) == 1_000_000_000_000 - 4_000_000, 5);
        assert!(bal(amm::pool_address(ta, tb), ta) == 1_000_000, 6);
    }

    #[test]
    #[expected_failure(abort_code = 15, location = aegis::amm)]
    fun first_deposit_at_minimum_liquidity_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000, 1_000); // sqrt = 1000, not > MINIMUM_LIQUIDITY
    }

    #[test]
    fun second_deposit_takes_only_ratio_matched_amounts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 4_000_000);
        // Bob offers far more B than the ratio needs; only 4e6 B may leave his wallet.
        amm::add_liquidity(&bob, ta, tb, 1_000_000, 9_000_000, 0, 0, DL);
        assert!(bal(@0xB0B, ta) == 1_000_000_000_000 - 1_000_000, 0);
        assert!(bal(@0xB0B, tb) == 1_000_000_000_000 - 4_000_000, 1);
        let lp = amm::lp_token(ta, tb);
        assert!(primary_fungible_store::balance(@0xB0B, lp) == 2_000_000, 2);
        assert!(amm::lp_total_supply(ta, tb) == 4_000_000, 3);
        // Reversed argument order must behave identically.
        amm::add_liquidity(&bob, tb, ta, 9_000_000, 1_000_000, 0, 0, DL);
        let (ra, rb) = amm::get_reserves(ta, tb);
        assert!(ra == 3_000_000 && rb == 12_000_000, 4);
    }

    #[test]
    #[expected_failure(abort_code = 7, location = aegis::amm)]
    fun add_liquidity_min_amount_violation_aborts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 4_000_000);
        amm::add_liquidity(&bob, ta, tb, 1_000_000, 9_000_000, 0, 5_000_000, DL);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = aegis::amm)]
    fun add_liquidity_without_pool_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        amm::add_liquidity(&alice, ta, tb, 1_000_000, 1_000_000, 0, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 4, location = aegis::amm)]
    fun add_liquidity_zero_amount_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        amm::create_pool(&alice, ta, tb);
        amm::add_liquidity(&alice, ta, tb, 0, 1_000_000, 0, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = aegis::amm)]
    fun add_liquidity_expired_deadline_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        amm::create_pool(&alice, ta, tb);
        amm::add_liquidity(&alice, ta, tb, 1_000_000, 1_000_000, 0, 0, 999);
    }

    #[test]
    #[expected_failure(abort_code = 11, location = aegis::amm)]
    fun reserve_overflow_aborts() {
        let (alice, bob, ta, tb) = fixture();
        th::mint(ta, @0xA11CE, 9_999_999_000_000_000_000);
        th::mint(tb, @0xA11CE, 9_999_999_000_000_000_000);
        th::mint(ta, @0xB0B, 9_999_999_000_000_000_000);
        th::mint(tb, @0xB0B, 9_999_999_000_000_000_000);
        pool_with(&alice, ta, tb, 10_000_000_000_000_000_000, 10_000_000_000_000_000_000);
        amm::add_liquidity(&bob, ta, tb, 10_000_000_000_000_000_000, 10_000_000_000_000_000_000, 0, 0, DL);
    }

    // -------------------------------------------------------------------- math
    #[test]
    fun get_amount_out_known_vector() {
        // 1000 * 997 * 100000 / (100000 * 1000 + 1000 * 997) = 987.15... -> 987
        assert!(amm::get_amount_out(1_000, 100_000, 100_000) == 987, 0);
        // Fee is exactly 0.30%: with a negligible price impact the output is ~99.7% of the input.
        let out = amm::get_amount_out(1_000_000, 1_000_000_000_000, 1_000_000_000_000);
        assert!(out == 996_999 || out == 997_000 || out == 996_998, 1);
    }

    #[test]
    #[expected_failure(abort_code = 4, location = aegis::amm)]
    fun get_amount_out_zero_input_aborts() {
        amm::get_amount_out(0, 100, 100);
    }

    #[test]
    #[expected_failure(abort_code = 17, location = aegis::amm)]
    fun get_amount_out_empty_reserve_aborts() {
        amm::get_amount_out(10, 0, 100);
    }

    // ------------------------------------------------------------------- swaps
    #[test]
    fun swap_updates_balances_reserves_and_grows_k() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        let k0 = k(ta, tb);
        let expected = amm::get_amount_out(1_000_000, E9, E9);
        let quoted = amm::quote_swap_out(ta, tb, 1_000_000);
        assert!(quoted == expected, 0);
        amm::swap_exact_in(&bob, ta, tb, 1_000_000, expected, DL);
        assert!(bal(@0xB0B, ta) == 1_000_000_000_000 - 1_000_000, 1);
        assert!(bal(@0xB0B, tb) == 1_000_000_000_000 + expected, 2);
        let (ra, rb) = amm::get_reserves(ta, tb);
        assert!(ra == E9 + 1_000_000 && rb == E9 - expected, 3);
        // Pool's real balances equal tracked reserves.
        assert!(bal(amm::pool_address(ta, tb), ta) == ra, 4);
        assert!(bal(amm::pool_address(ta, tb), tb) == rb, 5);
        assert!(k(ta, tb) > k0, 6);
        // User never receives more than input * 0.997 at equal reserves.
        assert!(expected < 1_000_000 * 997 / 1000 + 1, 7);
    }

    #[test]
    fun swap_reverse_direction_works() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, 2 * E9);
        let expected = amm::get_amount_out(1_000_000, 2 * E9, E9);
        amm::swap_exact_in(&bob, tb, ta, 1_000_000, expected, DL);
        let (ra, rb) = amm::get_reserves(ta, tb);
        assert!(ra == E9 - expected && rb == 2 * E9 + 1_000_000, 0);
        assert!(bal(@0xB0B, ta) == 1_000_000_000_000 + expected, 1);
    }

    #[test]
    #[expected_failure(abort_code = 6, location = aegis::amm)]
    fun swap_slippage_violation_aborts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        let expected = amm::get_amount_out(1_000_000, E9, E9);
        amm::swap_exact_in(&bob, ta, tb, 1_000_000, expected + 1, DL);
    }

    #[test]
    fun swap_exactly_min_out_succeeds() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        let expected = amm::get_amount_out(5_000_000, E9, E9);
        amm::swap_exact_in(&bob, ta, tb, 5_000_000, expected, DL);
    }

    #[test]
    #[expected_failure(abort_code = 4, location = aegis::amm)]
    fun swap_zero_input_aborts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        amm::swap_exact_in(&bob, ta, tb, 0, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = aegis::amm)]
    fun swap_same_token_aborts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        amm::swap_exact_in(&bob, ta, ta, 100, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = aegis::amm)]
    fun swap_without_pool_aborts() {
        let (_alice, bob, ta, tb) = fixture();
        amm::swap_exact_in(&bob, ta, tb, 100, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = aegis::amm)]
    fun swap_expired_deadline_aborts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        timestamp::update_global_time_for_test_secs(5000);
        amm::swap_exact_in(&bob, ta, tb, 1_000, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 6, location = aegis::amm)]
    fun swap_dust_with_zero_output_aborts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, 1_000_000); // price: 1 A buys ~0.001 B -> rounds to 0
        amm::swap_exact_in(&bob, ta, tb, 1, 0, DL);
    }

    #[test]
    #[expected_failure]
    fun swap_with_insufficient_balance_aborts() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        amm::swap_exact_in(&bob, ta, tb, 2_000_000_000_000, 0, DL); // Bob only holds 1e12
    }

    #[test]
    fun huge_swap_cannot_drain_pool() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        amm::swap_exact_in(&bob, ta, tb, 900_000_000_000, 0, DL);
        let (ra, rb) = amm::get_reserves(ta, tb);
        assert!(rb > 0, 0);
        assert!(ra == E9 + 900_000_000_000, 1);
        assert!(bal(amm::pool_address(ta, tb), tb) == rb, 2);
    }

    #[test]
    fun k_never_decreases_over_many_swaps() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, 3 * E9);
        let prev = k(ta, tb);
        let i = 1u64;
        while (i <= 20) {
            let amt = i * 7_919_003;
            if (i % 2 == 0) {
                amm::swap_exact_in(&bob, ta, tb, amt, 0, DL);
            } else {
                amm::swap_exact_in(&bob, tb, ta, amt, 0, DL);
            };
            let now = k(ta, tb);
            assert!(now >= prev, 100 + i);
            prev = now;
            i = i + 1;
        };
    }

    // --------------------------------------------------------- remove liquidity
    #[test]
    fun remove_all_liquidity_leaves_locked_minimum() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 4_000_000);
        let lp = amm::lp_token(ta, tb);
        amm::remove_liquidity(&alice, ta, tb, 1_999_000, 0, 0, DL);
        assert!(primary_fungible_store::balance(@0xA11CE, lp) == 0, 0);
        assert!(amm::lp_total_supply(ta, tb) == 1_000, 1);
        let (r0, r1) = amm::get_reserves(ta, tb);
        // 1999000 / 2000000 of each reserve is paid out; the 1000-unit share stays locked.
        assert!(r0 == 1_000_000 - 999_500 && r1 == 4_000_000 - 3_998_000, 2);
        assert!(bal(@0xA11CE, ta) == 1_000_000_000_000 - r0, 3);
        assert!(bal(@0xA11CE, tb) == 1_000_000_000_000 - r1, 4);
    }

    #[test]
    fun pool_remains_usable_after_full_withdrawal() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        amm::remove_liquidity(&alice, ta, tb, 999_000, 0, 0, DL);
        amm::add_liquidity(&bob, ta, tb, 5_000_000, 5_000_000, 0, 0, DL);
        amm::swap_exact_in(&bob, ta, tb, 10_000, 0, DL);
    }

    #[test]
    fun lp_tokens_are_transferable_and_redeemable_by_new_owner() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        let lp = amm::lp_token(ta, tb);
        primary_fungible_store::transfer(&alice, lp, @0xB0B, 500_000);
        amm::remove_liquidity(&bob, ta, tb, 500_000, 0, 0, DL);
        assert!(bal(@0xB0B, ta) == 1_000_000_000_000 + 500_000, 0);
        assert!(primary_fungible_store::balance(@0xA11CE, lp) == 499_000, 1);
    }

    #[test]
    #[expected_failure]
    fun cannot_withdraw_without_owning_lp() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        amm::remove_liquidity(&bob, ta, tb, 1_000, 0, 0, DL); // Bob holds no LP
    }

    #[test]
    #[expected_failure]
    fun cannot_remove_more_lp_than_owned() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        amm::add_liquidity(&bob, ta, tb, 1_000_000, 1_000_000, 0, 0, DL);
        amm::remove_liquidity(&bob, ta, tb, 1_000_001, 0, 0, DL); // Bob owns exactly 1_000_000
    }

    #[test]
    #[expected_failure(abort_code = 4, location = aegis::amm)]
    fun remove_zero_lp_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        amm::remove_liquidity(&alice, ta, tb, 0, 0, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 7, location = aegis::amm)]
    fun remove_liquidity_min_violation_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        amm::remove_liquidity(&alice, ta, tb, 500_000, 500_001, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 9, location = aegis::amm)]
    fun remove_dust_lp_rounding_to_zero_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        // 1 LP unit of a 1e6 supply yields exactly 1 of each; make one side round to 0.
        amm::swap_exact_in(&alice, ta, tb, 900_000, 0, DL); // skew reserves
        amm::remove_liquidity(&alice, tb, ta, 1, 0, 0, DL);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = aegis::amm)]
    fun remove_liquidity_expired_aborts() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, 1_000_000, 1_000_000);
        amm::remove_liquidity(&alice, ta, tb, 1_000, 0, 0, 999);
    }

    // ------------------------------------------------------------ fee accounting
    #[test]
    fun trading_fees_accrue_to_liquidity_providers() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        let i = 0;
        while (i < 10) {
            // Round trip: A -> B, then swap exactly what was received back B -> A.
            let b_before = bal(@0xB0B, tb);
            amm::swap_exact_in(&bob, ta, tb, 100_000_000, 0, DL);
            let received_b = bal(@0xB0B, tb) - b_before;
            amm::swap_exact_in(&bob, tb, ta, received_b, 0, DL);
            i = i + 1;
        };
        let a0 = bal(@0xA11CE, ta);
        let b0 = bal(@0xA11CE, tb);
        let lp = amm::lp_token(ta, tb);
        let lp_bal = primary_fungible_store::balance(@0xA11CE, lp);
        amm::remove_liquidity(&alice, ta, tb, lp_bal, 0, 0, DL);
        let got_a = bal(@0xA11CE, ta) - a0;
        let got_b = bal(@0xA11CE, tb) - b0;
        // Alice deposited 2e9 units in total; fees must have made her payout larger
        // even after the locked-minimum share (2000 units) is subtracted.
        assert!(got_a + got_b > 2 * E9, 0);
    }

    // -------------------------------------------------------- malicious inputs
    #[test]
    fun donation_cannot_change_price_or_reserves() {
        let (alice, bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        let quote_before = amm::quote_swap_out(ta, tb, 1_000_000);
        let pool_addr = amm::pool_address(ta, tb);
        primary_fungible_store::transfer(&bob, ta, pool_addr, 500_000_000_000);
        let (ra, rb) = amm::get_reserves(ta, tb);
        assert!(ra == E9 && rb == E9, 0);
        assert!(amm::quote_swap_out(ta, tb, 1_000_000) == quote_before, 1);
        // Donated tokens sit in the pool store but are unreachable (documented limitation).
        assert!(bal(pool_addr, ta) == E9 + 500_000_000_000, 2);
    }

    #[test]
    fun first_depositor_inflation_attack_does_not_hurt_victim() {
        let (alice, bob, ta, tb) = fixture();
        // Attacker: smallest possible first deposit (1 LP unit for the attacker), then donation.
        pool_with(&alice, ta, tb, 1_001, 1_001);
        let pool_addr = amm::pool_address(ta, tb);
        primary_fungible_store::transfer(&alice, ta, pool_addr, 500_000_000_000);
        primary_fungible_store::transfer(&alice, tb, pool_addr, 500_000_000_000);
        // Victim deposits normally and withdraws immediately: loses at most rounding dust.
        amm::add_liquidity(&bob, ta, tb, 1_000_000, 1_000_000, 0, 0, DL);
        let lp = amm::lp_token(ta, tb);
        let victim_lp = primary_fungible_store::balance(@0xB0B, lp);
        assert!(victim_lp > 0, 0);
        let a0 = bal(@0xB0B, ta);
        let b0 = bal(@0xB0B, tb);
        amm::remove_liquidity(&bob, ta, tb, victim_lp, 0, 0, DL);
        let got_a = bal(@0xB0B, ta) - a0;
        let got_b = bal(@0xB0B, tb) - b0;
        assert!(got_a + 2 >= 1_000_000 && got_b + 2 >= 1_000_000, 1);
    }

    #[test]
    #[expected_failure]
    fun cannot_call_pool_with_fake_token_object() {
        let (alice, _bob, ta, tb) = fixture();
        pool_with(&alice, ta, tb, E9, E9);
        // An address that is not a fungible-asset metadata object cannot be passed as a token.
        let fake = object::address_to_object<Metadata>(@0xDEAD);
        amm::swap_exact_in(&alice, fake, tb, 10, 0, DL);
    }

    #[test]
    fun signer_is_never_required_to_be_pool_creator() {
        let (_alice, bob, ta, tb) = fixture();
        amm::create_pool(&bob, ta, tb); // permissionless
        assert!(amm::pool_exists(ta, tb), 0);
        assert!(signer::address_of(&bob) == @0xB0B, 1);
    }
}

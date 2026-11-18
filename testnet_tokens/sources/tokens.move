/// TESTNET ONLY. Two freely mintable fungible assets used to smoke-test Aegis.
/// Never publish this package on mainnet.
module aegis_test::tokens {
    use std::option;
    use std::signer;
    use std::string;
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    const E_TOO_MUCH: u64 = 1;
    /// 1_000_000 tokens (8 decimals) per faucet call.
    const MAX_PER_CALL: u64 = 100_000_000_000_000;

    struct Refs has key { mint: MintRef }

    fun create(deployer: &signer, seed: vector<u8>, name: vector<u8>, symbol: vector<u8>) {
        let cref = object::create_named_object(deployer, seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &cref, option::none(), string::utf8(name), string::utf8(symbol), 8,
            string::utf8(b""), string::utf8(b"")
        );
        let mint = fungible_asset::generate_mint_ref(&cref);
        move_to(&object::generate_signer(&cref), Refs { mint });
    }

    fun init_module(deployer: &signer) {
        create(deployer, b"AEGIS_TEST_A", b"Aegis Test A", b"TSTA");
        create(deployer, b"AEGIS_TEST_B", b"Aegis Test B", b"TSTB");
    }

    #[view]
    public fun token_a(): Object<Metadata> {
        object::address_to_object<Metadata>(object::create_object_address(&@aegis_test, b"AEGIS_TEST_A"))
    }

    #[view]
    public fun token_b(): Object<Metadata> {
        object::address_to_object<Metadata>(object::create_object_address(&@aegis_test, b"AEGIS_TEST_B"))
    }

    /// Mint up to MAX_PER_CALL of token A and token B to the caller.
    public entry fun faucet(user: &signer, amount: u64) acquires Refs {
        assert!(amount <= MAX_PER_CALL, E_TOO_MUCH);
        let to = signer::address_of(user);
        let a = token_a();
        let b = token_b();
        primary_fungible_store::mint(&borrow_global<Refs>(object::object_address(&a)).mint, to, amount);
        primary_fungible_store::mint(&borrow_global<Refs>(object::object_address(&b)).mint, to, amount);
    }
}

#[test_only]
module aegis::test_helpers {
    use std::option;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aegis::amm;

    struct TokenRefs has key { mint: MintRef }

    /// Time starts at 1000s, factory deployed at @aegis.
    public fun setup() {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        timestamp::update_global_time_for_test_secs(1000);
        amm::init_for_test(&account::create_signer_for_test(@aegis));
    }

    public fun signer_of(addr: address): signer {
        account::create_signer_for_test(addr)
    }

    public fun create_token(creator: &signer, seed: vector<u8>): Object<Metadata> {
        let cref = object::create_named_object(creator, seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &cref, option::none(), string::utf8(b"Test Token"), string::utf8(b"TST"), 8,
            string::utf8(b""), string::utf8(b"")
        );
        let mint = fungible_asset::generate_mint_ref(&cref);
        move_to(&object::generate_signer(&cref), TokenRefs { mint });
        object::object_from_constructor_ref<Metadata>(&cref)
    }

    public fun mint(token: Object<Metadata>, to: address, amount: u64) acquires TokenRefs {
        let refs = borrow_global<TokenRefs>(object::object_address(&token));
        primary_fungible_store::mint(&refs.mint, to, amount);
    }

    public fun bal(owner: address, token: Object<Metadata>): u64 {
        primary_fungible_store::balance(owner, token)
    }
}

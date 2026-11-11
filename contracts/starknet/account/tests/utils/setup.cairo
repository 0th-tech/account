// Project
use account::account::IAccountDispatcher;

// Snforge
use snforge_std::start_cheat_block_timestamp_global;

// Tests
use crate::utils::helpers::{
    EXPIRY, IDENTITY_INPUT, MODULUS_LIMBS, deploy_contract, load_proof, public_inputs,
};

pub fn setup(verifier: ByteArray, identity_hash: u256, with_key: bool) -> IAccountDispatcher {
    // The clock starts one day before the fixture expires
    start_cheat_block_timestamp_global(EXPIRY - 24 * 3600);

    // Registry, holding the fixture's key or none
    let inputs = public_inputs(load_proof().span());
    let modulus = if with_key {
        inputs.span().slice(0, MODULUS_LIMBS)
    } else {
        array![].span()
    };
    let mut calldata = array![];
    Serde::serialize(@modulus, ref calldata);
    let registry_address = deploy_contract("MockRegistry", calldata);

    // Verifier
    let verifier_address = deploy_contract(verifier, array![]);

    // Account
    let mut calldata = array![];
    Serde::serialize(@registry_address, ref calldata);
    Serde::serialize(@verifier_address, ref calldata);
    Serde::serialize(@identity_hash, ref calldata);
    let contract_address = deploy_contract("Account", calldata);

    IAccountDispatcher { contract_address }
}

pub fn fixture_identity() -> u256 {
    *public_inputs(load_proof().span())[IDENTITY_INPUT]
}

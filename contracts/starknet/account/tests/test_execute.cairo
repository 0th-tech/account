// Project
use account::account::{IAccountDispatcher, IAccountDispatcherTrait};

// OpenZeppelin
use openzeppelin_interfaces::accounts::{ISRC6Dispatcher, ISRC6DispatcherTrait, ISRC6_ID};
use openzeppelin_interfaces::introspection::{ISRC5Dispatcher, ISRC5DispatcherTrait};

// Snforge
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use snforge_std::start_cheat_block_timestamp_global;

// Starknet
use starknet::account::Call;

// Tests
use crate::utils::helpers::{
    EXPIRY, SESSION_PRIVKEY, TX_HASH, cheat_tx, load_proof, mock_proof, public_inputs, session_key,
    session_signature,
};
use crate::utils::setup::{fixture_identity, setup};

/// Deploys an account holding the fixture's session
fn setup_session() -> IAccountDispatcher {
    let account = setup("MockVerifier", fixture_identity(), true);
    let inputs = public_inputs(load_proof().span());
    account.register_session(mock_proof(inputs.span()).span());
    account
}

/// The account's SRC6 entry points: __validate__, __execute__ and is_valid_signature
fn src6(account: IAccountDispatcher) -> ISRC6Dispatcher {
    ISRC6Dispatcher { contract_address: account.contract_address }
}

#[test]
fn test_fixture_session_key() {
    let inputs = public_inputs(load_proof().span());

    let key_pair = StarkCurveKeyPairImpl::from_secret_key(SESSION_PRIVKEY);

    assert_eq!(key_pair.public_key, session_key(inputs.span()));
}

#[test]
fn test_validate() {
    let account = setup_session();
    cheat_tx(account.contract_address, session_signature(TX_HASH).span());

    let result = src6(account).__validate__(array![]);

    assert_eq!(result, starknet::VALIDATED);
}

#[test]
#[should_panic(expected: ('invalid session', 'ENTRYPOINT_FAILED'))]
fn test_validate_unknown_session() {
    let account = setup("MockVerifier", fixture_identity(), true);
    cheat_tx(account.contract_address, session_signature(TX_HASH).span());

    src6(account).__validate__(array![]); // (must panic)
}

#[test]
#[should_panic(expected: ('invalid session', 'ENTRYPOINT_FAILED'))]
fn test_validate_expired_session() {
    let account = setup_session();
    cheat_tx(account.contract_address, session_signature(TX_HASH).span());
    start_cheat_block_timestamp_global(EXPIRY);

    src6(account).__validate__(array![]); // (must panic)
}

#[test]
#[should_panic(expected: ('invalid signature', 'ENTRYPOINT_FAILED'))]
fn test_validate_wrong_tx_hash() {
    let account = setup_session();
    cheat_tx(account.contract_address, session_signature(TX_HASH + 1).span());

    src6(account).__validate__(array![]); // (must panic)
}

#[test]
#[should_panic(expected: ('invalid signature length', 'ENTRYPOINT_FAILED'))]
fn test_validate_signature_without_key() {
    let account = setup_session();
    cheat_tx(account.contract_address, session_signature(TX_HASH).span().slice(1, 2));

    src6(account).__validate__(array![]); // (must panic)
}

#[test]
fn test_supports_src6() {
    let account = setup("MockVerifier", fixture_identity(), true);

    // A dapp looks the account up by this id before trusting is_valid_signature
    let src5 = ISRC5Dispatcher { contract_address: account.contract_address };

    assert!(src5.supports_interface(ISRC6_ID));
}

#[test]
fn test_is_valid_signature() {
    let account = setup_session();

    let result = src6(account).is_valid_signature(TX_HASH, session_signature(TX_HASH));

    assert_eq!(result, starknet::VALIDATED);
}

#[test]
fn test_is_valid_signature_rejected() {
    let account = setup_session();
    let signature = session_signature(TX_HASH);

    // A real signature of another hash
    assert_eq!(src6(account).is_valid_signature(TX_HASH + 1, signature.clone()), 0);

    // A plain [r, s], as wallet libraries send it
    assert_eq!(src6(account).is_valid_signature(TX_HASH, array![*signature[1], *signature[2]]), 0);

    // The clock is at the session's expiry
    start_cheat_block_timestamp_global(EXPIRY);
    assert_eq!(src6(account).is_valid_signature(TX_HASH, signature), 0);
}

#[test]
fn test_is_valid_signature_unknown_session() {
    let account = setup("MockVerifier", fixture_identity(), true);

    // An unregistered key has expiry 0, so it fails like an expired one
    assert_eq!(src6(account).is_valid_signature(TX_HASH, session_signature(TX_HASH)), 0);
}

#[test]
fn test_execute() {
    let account = setup("MockVerifier", fixture_identity(), true);
    let inputs = public_inputs(load_proof().span());
    let mut calldata = array![];
    Serde::serialize(@mock_proof(inputs.span()).span(), ref calldata);
    let call = Call {
        to: account.contract_address,
        selector: selector!("register_session"),
        calldata: calldata.span(),
    };
    cheat_tx(account.contract_address, session_signature(TX_HASH).span());

    src6(account).__execute__(array![call]);

    assert_eq!(account.get_session_expiry(session_key(inputs.span())), EXPIRY);
}

#[test]
#[should_panic(expected: ('invalid caller', 'ENTRYPOINT_FAILED'))]
fn test_execute_from_contract() {
    let account = setup_session();

    src6(account).__execute__(array![]); // (must panic)
}

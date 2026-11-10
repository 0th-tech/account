// Project
use account::account::{IAccountDispatcherTrait, MAX_SESSION};

// Snforge
use snforge_std::start_cheat_block_timestamp_global;

// Tests
use crate::utils::helpers::{
    EXPIRY, SESSION_KEY_INPUT, load_proof, mock_proof, public_inputs, replace_input, session_key,
};
use crate::utils::setup::{fixture_identity, setup};

#[test]
fn test_register_session() {
    let account = setup("MockVerifier", fixture_identity(), true);
    let inputs = public_inputs(load_proof().span());

    account.register_session(mock_proof(inputs.span()).span());

    assert_eq!(account.get_session_expiry(session_key(inputs.span())), EXPIRY);
}

#[test]
#[should_panic(expected: ('wrong identity', 'ENTRYPOINT_FAILED'))]
fn test_register_session_wrong_identity() {
    // A real proof, but for another user's account
    let account = setup("MockVerifier", fixture_identity() + 1, true);
    let inputs = public_inputs(load_proof().span());

    account.register_session(mock_proof(inputs.span()).span()); // (must panic)
}

#[test]
#[should_panic(expected: ('unknown provider key', 'ENTRYPOINT_FAILED'))]
fn test_register_session_unknown_key() {
    // The registry holds no key, so the chain cannot tell this one is the provider's
    let account = setup("MockVerifier", fixture_identity(), false);
    let inputs = public_inputs(load_proof().span());

    account.register_session(mock_proof(inputs.span()).span()); // (must panic)
}

#[test]
#[should_panic(expected: ('session expired', 'ENTRYPOINT_FAILED'))]
fn test_register_session_expired() {
    let account = setup("MockVerifier", fixture_identity(), true);
    let inputs = public_inputs(load_proof().span());

    // The clock reaches the session's expiry, so there is nothing left to register
    start_cheat_block_timestamp_global(EXPIRY);

    account.register_session(mock_proof(inputs.span()).span()); // (must panic)
}

// The only test running the real verifier, the others mock it away
#[test]
fn test_register_session_real_proof() {
    let account = setup("UltraKeccakZKHonkVerifier", fixture_identity(), true);
    let proof = load_proof();
    let inputs = public_inputs(proof.span());

    account.register_session(proof.span());

    assert_eq!(account.get_session_expiry(session_key(inputs.span())), EXPIRY);
}

// Garaga panics in its hint check before it can return 'invalid proof'
#[test]
#[should_panic(
    expected: ('Wrong GLV/FakeGLV decomposition', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'),
)]
fn test_register_session_real_proof_tampered_session_key() {
    let account = setup("UltraKeccakZKHonkVerifier", fixture_identity(), true);
    let mut proof = load_proof();
    let inputs = public_inputs(proof.span());

    // Put another session key in the proof, 2, and keep the rest of it as it was
    let tampered = replace_input(inputs.span(), SESSION_KEY_INPUT, 2);
    let mut tampered_proof = mock_proof(tampered.span());
    for i in (1 + 2 * tampered.len())..proof.len() {
        tampered_proof.append(*proof[i]);
    }

    account.register_session(tampered_proof.span()); // (must panic)
}

#[test]
#[should_panic(expected: ('session too long', 'ENTRYPOINT_FAILED'))]
fn test_register_session_too_long() {
    let account = setup("MockVerifier", fixture_identity(), true);
    let inputs = public_inputs(load_proof().span());

    // One second too early, so the session now asks for more than MAX_SESSION
    start_cheat_block_timestamp_global(EXPIRY - MAX_SESSION - 1);

    account.register_session(mock_proof(inputs.span()).span()); // (must panic)
}

#[test]
#[should_panic(expected: ('session already registered', 'ENTRYPOINT_FAILED'))]
fn test_register_session_replay() {
    let account = setup("MockVerifier", fixture_identity(), true);
    let proof = mock_proof(public_inputs(load_proof().span()).span());
    account.register_session(proof.span());

    // Anyone can read the proof off the chain and send it again
    account.register_session(proof.span()); // (must panic)
}

// Core
use core::num::traits::Zero;

// Snforge
use snforge_std::fs::{FileTrait, read_txt};
use snforge_std::signature::stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    start_cheat_signature_global, start_cheat_transaction_hash_global,
    start_cheat_transaction_version_global,
};

// Starknet
use starknet::{ContractAddress, SyscallResultTrait};

// From the circuit's fixture letter
pub const EXPIRY: u64 = 1800000000;
pub const SESSION_PRIVKEY: felt252 = 0x1234567890abcdef;

pub const TX_HASH: felt252 = 'TX_HASH';

// Public values of the circuit, by position
pub const IDENTITY_INPUT: u32 = 0;
pub const KEY_HASH_INPUT: u32 = 1;
pub const SESSION_KEY_INPUT: u32 = 3;

// Garaga's Groth16 calldata starts with the proof's three points (A, B, C as u384 coordinates),
// then the public values: count, (low, high) * count
pub const PROOF_POINTS_FELTS: u32 = 32;

pub fn deploy_contract(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let contract = declare(name).unwrap_syscall().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap_syscall();
    contract_address
}

/// Loads the Garaga calldata of the circuit's proof fixture (make verifier)
pub fn load_proof() -> Array<felt252> {
    read_txt(@FileTrait::new("../verifier/tests/proof_calldata.txt"))
}

/// Reads the public values of a proof's calldata
pub fn public_inputs(proof: Span<felt252>) -> Array<u256> {
    let count: u32 = (*proof[PROOF_POINTS_FELTS]).try_into().unwrap();
    let mut inputs = array![];
    for i in 0..count {
        let low = (*proof[PROOF_POINTS_FELTS + 1 + 2 * i]).try_into().unwrap();
        let high = (*proof[PROOF_POINTS_FELTS + 2 + 2 * i]).try_into().unwrap();
        inputs.append(u256 { low, high });
    }
    inputs
}

/// Encodes public inputs as a proof for the MockVerifier
pub fn mock_proof(inputs: Span<u256>) -> Array<felt252> {
    let mut proof = array![inputs.len().into()];
    for input in inputs {
        proof.append((*input.low).into());
        proof.append((*input.high).into());
    }
    proof
}

/// The session key the proof registers
pub fn session_key(inputs: Span<u256>) -> felt252 {
    (*inputs[SESSION_KEY_INPUT]).try_into().unwrap()
}

/// Signs a tx hash with the fixture session key, as the account expects: [session_key, r, s]
pub fn session_signature(tx_hash: felt252) -> Array<felt252> {
    let key_pair = StarkCurveKeyPairImpl::from_secret_key(SESSION_PRIVKEY);
    let (r, s) = key_pair.sign(tx_hash).unwrap();
    array![key_pair.public_key, r, s]
}

/// Makes the next calls to the account look like a transaction sent by the protocol
pub fn cheat_tx(account: ContractAddress, signature: Span<felt252>) {
    start_cheat_transaction_hash_global(TX_HASH);
    start_cheat_signature_global(signature);
    start_cheat_transaction_version_global(3);
    start_cheat_caller_address(account, Zero::zero());
}

#[starknet::interface]
pub trait IAccount<TContractState> {
    fn register_session(ref self: TContractState, proof: Span<felt252>);
    fn get_session_expiry(self: @TContractState, session_key: felt252) -> u64;
}

// The one key registry function the account calls, matched by selector
#[starknet::interface]
pub trait IKeyRegistry<TContractState> {
    fn is_key(self: @TContractState, modulus: Span<u256>) -> bool;
}

// Longest session a proof may ask for (30 days)
pub const MAX_SESSION: u64 = 30 * 24 * 3600;

#[starknet::contract(account)]
pub mod Account {
    // Core
    use core::num::traits::Zero;

    // OpenZeppelin
    use openzeppelin_account::utils::{is_tx_version_valid, is_valid_stark_signature};
    use openzeppelin_interfaces::accounts::ISRC6_ID;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_utils::execution::execute_calls;

    // Starknet
    use starknet::account::Call;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_tx_info};

    // Verifier
    use verifier::honk_verifier::{
        IUltraKeccakZKHonkVerifierDispatcher, IUltraKeccakZKHonkVerifierDispatcherTrait,
    };
    use super::{IKeyRegistryDispatcher, IKeyRegistryDispatcherTrait, MAX_SESSION};

    // Position of each public input of the login circuit's proof
    const MODULUS_LIMBS: usize = 18;
    const SESSION_KEY_INPUT: usize = 18;
    const EXPIRY_INPUT: usize = 19;
    const IDENTITY_INPUT: usize = 20;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        registry: ContractAddress,
        verifier: ContractAddress,
        identity_hash: u256, // H(iss, aud, sub, salt), BN254 field element
        sessions: Map<felt252, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        registry: ContractAddress,
        verifier: ContractAddress,
        identity_hash: u256,
    ) {
        self.src5.register_interface(ISRC6_ID);

        self.registry.write(registry);
        self.verifier.write(verifier);
        self.identity_hash.write(identity_hash);
    }

    #[abi(embed_v0)]
    impl AccountImpl of super::IAccount<ContractState> {
        fn register_session(ref self: ContractState, proof: Span<felt252>) {
            // Verify the proof
            let inputs = IUltraKeccakZKHonkVerifierDispatcher {
                contract_address: self.verifier.read(),
            }
                .verify_ultra_keccak_zk_honk_proof(proof)
                .expect('invalid proof');

            // Read the public inputs
            let modulus = inputs.slice(0, MODULUS_LIMBS);
            // u256 to felt252 fails above the stark prime, a big key is rejected
            let session_key: felt252 = (*inputs[SESSION_KEY_INPUT])
                .try_into()
                .expect('session key too large');
            let expiry: u64 = (*inputs[EXPIRY_INPUT]).try_into().unwrap();
            let identity_hash = *inputs[IDENTITY_INPUT];

            // Check the proof is for this account
            assert(identity_hash == self.identity_hash.read(), 'wrong identity');

            // Check the signing key is the provider's (the proof holds for any RSA key)
            assert(
                IKeyRegistryDispatcher { contract_address: self.registry.read() }.is_key(modulus),
                'unknown provider key',
            );

            // Check the expiry
            let now = get_block_timestamp();
            assert(expiry > now, 'session expired');
            assert(expiry <= now + MAX_SESSION, 'session too long');

            // Proofs are public on chain, so a replayed one is refused
            assert(self.sessions.read(session_key) == 0, 'session already registered');

            // Store the session
            self.sessions.write(session_key, expiry);
        }

        fn get_session_expiry(self: @ContractState, session_key: felt252) -> u64 {
            self.sessions.read(session_key)
        }
    }

    // Each cause asserts separately, so a transaction that fails validation names why
    #[external(v0)]
    fn __validate__(self: @ContractState, calls: Array<Call>) -> felt252 {
        let tx_info = get_tx_info().unbox();
        let signature = tx_info.signature;
        assert(signature.len() == 3, 'invalid signature length');
        assert(live_session(self, signature), 'invalid session');
        assert(signed_by_session(tx_info.transaction_hash, signature), 'invalid signature');
        starknet::VALIDATED
    }

    #[external(v0)]
    fn is_valid_signature(
        self: @ContractState, hash: felt252, signature: Array<felt252>,
    ) -> felt252 {
        let signature = signature.span();
        let valid = signature.len() == 3
            && live_session(self, signature)
            && signed_by_session(hash, signature);
        if valid {
            starknet::VALIDATED
        } else {
            0
        }
    }

    // Session key signature [session_key, r, s] must be registered and not expired
    fn live_session(self: @ContractState, signature: Span<felt252>) -> bool {
        get_block_timestamp() < self.sessions.read(*signature[0])
    }

    // Checks that the session key signed the given hash
    fn signed_by_session(hash: felt252, signature: Span<felt252>) -> bool {
        is_valid_stark_signature(hash, *signature[0], signature.slice(1, 2))
    }

    #[external(v0)]
    fn __execute__(self: @ContractState, calls: Array<Call>) {
        assert(get_caller_address().is_zero(), 'invalid caller');
        assert(is_tx_version_valid(), 'invalid tx version');

        execute_calls(calls.span());
    }
}

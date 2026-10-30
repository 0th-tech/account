#[starknet::contract]
pub mod MockRegistry {
    // Core
    use core::poseidon::poseidon_hash_span;

    // Starknet
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // Holds the one key set at deploy, so a test sees which modulus the account asks about
    #[storage]
    struct Storage {
        key: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, modulus: Span<u256>) {
        self.key.write(key_id(modulus));
    }

    #[abi(embed_v0)]
    impl MockRegistryImpl of account::account::IKeyRegistry<ContractState> {
        fn is_key(self: @ContractState, modulus: Span<u256>) -> bool {
            key_id(modulus) == self.key.read()
        }
    }

    fn key_id(modulus: Span<u256>) -> felt252 {
        let mut felts = array![];
        modulus.serialize(ref felts);
        poseidon_hash_span(felts.span())
    }
}

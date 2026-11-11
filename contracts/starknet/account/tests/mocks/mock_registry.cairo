#[starknet::contract]
pub mod MockRegistry {
    // Core
    use core::poseidon::poseidon_hash_span;

    // Starknet
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // The mock knows only the key set at deploy, so the account must ask about that modulus
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

#[starknet::contract]
pub mod MockRegistry {
    // Starknet
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // The mock knows only the key set at deploy, so the account must ask about that key
    #[storage]
    struct Storage {
        key_hash: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, key_hash: u256) {
        self.key_hash.write(key_hash);
    }

    #[abi(embed_v0)]
    impl MockRegistryImpl of account::account::IKeyRegistry<ContractState> {
        fn is_key(self: @ContractState, key_hash: u256) -> bool {
            key_hash == self.key_hash.read()
        }
    }
}

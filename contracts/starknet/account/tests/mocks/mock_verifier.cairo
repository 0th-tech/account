#[starknet::contract]
pub mod MockVerifier {
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MockVerifierImpl of verifier::groth16_verifier::IGroth16VerifierBN254<ContractState> {
        // The mock returns the public inputs without checking a proof
        fn verify_groth16_proof_bn254(
            self: @ContractState, full_proof_with_hints: Span<felt252>,
        ) -> Result<Span<u256>, felt252> {
            let count: u32 = (*full_proof_with_hints.at(0)).try_into().unwrap();
            let mut inputs = array![];
            for i in 0..count {
                let low: u128 = (*full_proof_with_hints.at(1 + 2 * i)).try_into().unwrap();
                let high: u128 = (*full_proof_with_hints.at(2 + 2 * i)).try_into().unwrap();
                inputs.append(u256 { low, high });
            }
            Result::Ok(inputs.span())
        }
    }
}

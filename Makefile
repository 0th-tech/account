.PHONY: image circuit verifier test clean fclean fmt fmt-check

CONTRACT = contracts/starknet
VERIFIER = $(CONTRACT)/verifier
SYSTEM = ultra_keccak_zk_honk
IMAGE = 0th-account-tools
CIRCUIT_VERSION ?= v0.1.0
CIRCUIT_RELEASE = https://github.com/0th-tech/circuit/releases/download/$(CIRCUIT_VERSION)

image:
	docker build -t $(IMAGE) - < $(CONTRACT)/Dockerfile

RUN = docker run --rm --user "$$(id -u):$$(id -g)" -v "$$(pwd)":/work $(IMAGE) bash -c

# target/circuit/{vk,proof,public_inputs}, from the circuit's release
circuit:
	mkdir -p target/circuit
	for file in vk proof public_inputs; do \
		curl -fsSL $(CIRCUIT_RELEASE)/$$file -o target/circuit/$$file || exit 1; \
	done

# Garaga warns that bb and nargo are missing, which is harmless: the vk comes from the circuit release
verifier: image circuit
	$(RUN) '\
		rm -rf /tmp/verifier && \
		(cd /tmp && garaga gen --system $(SYSTEM) --vk /work/target/circuit/vk --project-name verifier) && \
		rm -f $(VERIFIER)/src/*.cairo && \
		cp /tmp/verifier/src/*.cairo $(VERIFIER)/src/ && \
		cp /tmp/verifier/tests/test_contract.cairo $(VERIFIER)/tests/ && \
		garaga calldata --system $(SYSTEM) --vk target/circuit/vk --proof target/circuit/proof \
			--public-inputs target/circuit/public_inputs --format snforge --output-path $(VERIFIER)/tests \
	'
	cd $(VERIFIER) && scarb fmt

test:
	cd $(CONTRACT) && snforge test

clean:
	rm -rf target $(CONTRACT)/target

fclean: clean
	docker rmi $(IMAGE) 2>/dev/null || true

fmt:
	cd $(CONTRACT) && scarb fmt

fmt-check:
	cd $(CONTRACT) && scarb fmt --check

.PHONY: image verifier deploy deploy-verifier declare-account build test clean fclean fmt fmt-check

NETWORK ?= devnet

# A download that fails leaves no partial file behind
.DELETE_ON_ERROR:

CONTRACT = contracts/starknet
VERIFIER_DIR = $(CONTRACT)/verifier
SYSTEM = ultra_keccak_zk_honk
IMAGE = 0th-account-tools
CIRCUIT_VERSION ?= v0.1.0
CIRCUIT_RELEASE = https://github.com/0th-tech/circuit/releases/download/$(CIRCUIT_VERSION)
DEPLOYMENT = deployments/$(NETWORK).env

-include .env.$(NETWORK)
export

image:
	docker build -t $(IMAGE) - < $(CONTRACT)/Dockerfile

RUN = docker run --rm --user "$$(id -u):$$(id -g)" -v "$$(pwd)":/work $(IMAGE) bash -c

# A file from the circuit's release, downloaded again whenever this Makefile changes, since it pins the version
target/circuit/%: Makefile
	mkdir -p $(@D)
	curl -fsSL $(CIRCUIT_RELEASE)/$* -o $@

# Garaga warns that bb and nargo are missing, which is harmless: the vk comes from the circuit release
verifier: image target/circuit/vk target/circuit/proof target/circuit/public_inputs
	$(RUN) '\
		rm -rf /tmp/verifier && \
		(cd /tmp && garaga gen --system $(SYSTEM) --vk /work/target/circuit/vk --project-name verifier) && \
		rm -f $(VERIFIER_DIR)/src/*.cairo && \
		cp /tmp/verifier/src/*.cairo $(VERIFIER_DIR)/src/ && \
		cp /tmp/verifier/tests/test_contract.cairo $(VERIFIER_DIR)/tests/ && \
		garaga calldata --system $(SYSTEM) --vk target/circuit/vk --proof target/circuit/proof \
			--public-inputs target/circuit/public_inputs --format snforge --output-path $(VERIFIER_DIR)/tests \
	'
	cd $(VERIFIER_DIR) && scarb fmt

# Network targets: make <target> NETWORK=<devnet|sepolia|mainnet>, devnet by default

deploy: deploy-verifier declare-account

SET = mkdir -p deployments && touch $(DEPLOYMENT) && \
	{ grep -v "^$(1)=" $(DEPLOYMENT); echo "$(1)=$$value"; } > $(DEPLOYMENT).tmp && \
	mv $(DEPLOYMENT).tmp $(DEPLOYMENT) && echo "$(1)=$$value"

deploy-verifier:
	value=$$(cd $(CONTRACT) && sncast --profile $(NETWORK) --json deploy --package verifier \
		--contract-name UltraKeccakZKHonkVerifier --salt 0x0 | jq -eRr 'fromjson? | select(.type == "response").contract_address') && \
		$(call SET,VERIFIER)

# Accounts are deployed by the relayer, one per user, so only the class is declared here
declare-account:
	value=$$(cd $(CONTRACT) && sncast --profile $(NETWORK) --json declare --package account \
		--contract-name Account | jq -eRr 'fromjson? | select(.type == "response").class_hash') && \
		$(call SET,ACCOUNT_CLASS_HASH)

build:
	cd $(CONTRACT) && scarb --release build

test:
	cd $(CONTRACT) && snforge test

clean:
	rm -rf target $(CONTRACT)/target
	rm -f deployments/devnet.env

fclean: clean
	docker rmi $(IMAGE) 2>/dev/null || true

fmt:
	cd $(CONTRACT) && scarb fmt

fmt-check:
	cd $(CONTRACT) && scarb fmt --check

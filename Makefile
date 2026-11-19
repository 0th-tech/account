.PHONY: image verifier deploy declare-garaga deploy-verifier declare-account build test clean fclean fmt fmt-check FORCE

NETWORK ?= devnet

# A download that fails leaves no partial file behind
.DELETE_ON_ERROR:

CONTRACT = contracts/starknet
VERIFIER_DIR = $(CONTRACT)/verifier
SYSTEM = groth16
IMAGE = 0th-account-tools
CIRCUIT_VERSION ?= v0.2.0
CIRCUIT_RELEASE = https://github.com/0th-tech/circuit/releases/download/$(CIRCUIT_VERSION)
DEPLOYMENT = deployments/$(NETWORK).env

-include .env.$(NETWORK)
export

image:
	docker build -t $(IMAGE) - < $(CONTRACT)/Dockerfile

RUN = docker run --rm --user "$$(id -u):$$(id -g)" -v "$$(pwd)":/work $(IMAGE) bash -c

# The pinned source of the downloads below. A new pin rewrites this file, so they download again
target/.pins: FORCE
	@mkdir -p $(@D) && echo '$(CIRCUIT_RELEASE)' | cmp -s - $@ || echo '$(CIRCUIT_RELEASE)' > $@

target/circuit/%: target/.pins
	mkdir -p $(@D)
	curl -fsSL $(CIRCUIT_RELEASE)/$* -o $@

verifier: image target/circuit/vk.json target/circuit/proof.json target/circuit/public.json
	$(RUN) '\
		rm -rf /tmp/verifier && \
		(cd /tmp && garaga gen --system $(SYSTEM) --vk /work/target/circuit/vk.json --project-name verifier) && \
		rm -f $(VERIFIER_DIR)/src/*.cairo && \
		cp /tmp/verifier/src/*.cairo $(VERIFIER_DIR)/src/ && \
		cp /tmp/verifier/tests/test_contract.cairo $(VERIFIER_DIR)/tests/ && \
		garaga calldata --system $(SYSTEM) --vk target/circuit/vk.json --proof target/circuit/proof.json \
			--public-inputs target/circuit/public.json --format snforge --output-path $(VERIFIER_DIR)/tests \
	'
	cd $(VERIFIER_DIR) && scarb fmt

# Network targets: make <target> NETWORK=<devnet|sepolia|mainnet>, devnet by default

# Garaga's verifier library-calls Garaga's MSM class by this hash. Garaga declared it on Sepolia and
# mainnet, so a devnet gets the same class from Sepolia
GARAGA_MSM_CLASS = 0x396d5915ecf475aab117bb25a0272b261e9e25ffe1c0ce05a51a3f77489c89e

deploy: $(if $(filter devnet,$(NETWORK)),declare-garaga) deploy-verifier declare-account

declare-garaga:
	cd $(CONTRACT) && sncast --profile $(NETWORK) declare-from --class-hash $(GARAGA_MSM_CLASS) \
		--source-network sepolia

SET = mkdir -p deployments && touch $(DEPLOYMENT) && \
	{ grep -v "^$(1)=" $(DEPLOYMENT); echo "$(1)=$$value"; } > $(DEPLOYMENT).tmp && \
	mv $(DEPLOYMENT).tmp $(DEPLOYMENT) && echo "$(1)=$$value"

deploy-verifier:
	value=$$(cd $(CONTRACT) && sncast --profile $(NETWORK) --json deploy --package verifier \
		--contract-name Groth16VerifierBN254 --salt 0x0 | jq -eRr 'fromjson? | select(.type == "response").contract_address') && \
		$(call SET,VERIFIER)

# Accounts are deployed by the relayer, one per user, so only the class is declared here
declare-account:
	value=$$(cd $(CONTRACT) && sncast --profile $(NETWORK) --json declare --package account \
		--contract-name Account | jq -eRr 'fromjson? | select(.type == "response").class_hash') && \
		$(call SET,ACCOUNT_CLASS_HASH)

build:
	cd $(CONTRACT) && scarb --release build

# The public Sepolia RPC the fork tests read from refuses requests that arrive too fast, so the tests
# run one at a time
test:
	cd $(CONTRACT) && snforge test --max-threads 1

clean:
	rm -rf target $(CONTRACT)/target
	rm -f deployments/devnet.env

fclean: clean
	docker rmi $(IMAGE) 2>/dev/null || true

fmt:
	cd $(CONTRACT) && scarb fmt

fmt-check:
	cd $(CONTRACT) && scarb fmt --check

# Makefile for Capital Distributor Plugin Scripts

# Use bash shell for better compatibility
SHELL := /bin/bash

# Load environment variables from .env file if it exists
-include .env

# Default RPC URL if not set
RPC_URL ?= http://localhost:8545

# Colors - using printf format
COLOR_YELLOW := \033[0;33m
COLOR_GREEN := \033[0;32m
COLOR_RESET := \033[0m

.PHONY: help
help: ## Show this help message
	@printf "Usage:\n"
	@printf "  $${COLOR_YELLOW}make$${COLOR_RESET} $${COLOR_GREEN}<target>$${COLOR_RESET}\n"
	@printf "\n"
	@printf "Targets:\n"
	@awk -F':.*?##' -v yellow="$(COLOR_YELLOW)" -v reset="$(COLOR_RESET)" '/^[a-zA-Z_-]+:.*?##/ {printf "  %s%-25s%s %s\n", yellow, $$1, reset, $$2}' $(MAKEFILE_LIST) | sort

# ===== Campaign Management =====

.PHONY: create-campaign
create-campaign: ## Create a new Merkle campaign through Admin plugin
	@printf "$${COLOR_GREEN}Creating Merkle campaign...$${COLOR_RESET}\n"
	@forge script script/utils/CreateMerkleCampaign.s.sol:CreateMerkleCampaign \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvv

.PHONY: create-campaign-dry
create-campaign-dry: ## Dry run of campaign creation (no broadcast)
	@printf "$${COLOR_YELLOW}Dry run: Creating Merkle campaign...$${COLOR_RESET}\n"
	@forge script script/utils/CreateMerkleCampaign.s.sol:CreateMerkleCampaign \
		--private-key $(PRIVATE_KEY) \
		-vvv

.PHONY: claim
claim: ## Claim tokens from a Merkle campaign
	@echo "Claiming from Merkle campaign..."
	@forge script script/utils/ClaimMerkleCampaign.s.sol:ClaimMerkleCampaign \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvv

.PHONY: claim-dry
claim-dry: ## Dry run of claim (no broadcast)
	@echo "Dry run: Claiming from Merkle campaign..."
	@forge script script/utils/ClaimMerkleCampaign.s.sol:ClaimMerkleCampaign \
		--private-key $(PRIVATE_KEY) \
		-vvv

.PHONY: claim-all-proofs
claim-all-proofs: ## Claim tokens for all proof files in fixtures/proofs
	@printf "$${COLOR_GREEN}Processing all proof files...$${COLOR_RESET}\n"
	@forge script script/utils/ClaimMerkleCampaignWithProofs.s.sol:ClaimMerkleCampaignWithProofs \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvv

.PHONY: claim-all-proofs-dry
claim-all-proofs-dry: ## Claim tokens for all proof files in fixtures/proofs
	@printf "$${COLOR_GREEN}Processing all proof files...$${COLOR_RESET}\n"
	@forge script script/utils/ClaimMerkleCampaignWithProofs.s.sol:ClaimMerkleCampaignWithProofs \
		--private-key $(PRIVATE_KEY) \
		-vvv

.PHONY: claim-proof-file-dry
claim-proof-file: ## Claim for a specific proof file (use PROOF_FILE=filename.json)
	@if [ -z "$(PROOF_FILE)" ]; then \
		printf "$${COLOR_YELLOW}⚠️  Please set PROOF_FILE=filename.json$${COLOR_RESET}\n"; \
		exit 1; \
	fi
	@printf "$${COLOR_GREEN}Claiming from proof file: $(PROOF_FILE)$${COLOR_RESET}\n"
	@forge script script/utils/ClaimMerkleCampaignWithProofs.s.sol:ClaimMerkleCampaignWithProofs \
		--private-key $(PRIVATE_KEY) \
		--sig "claimForFile(string)" \
		"$(PROOF_FILE)" \
		-vvv

# ===== Environment Setup =====

.PHONY: check-env
check-env: ## Check if required environment variables are set
	@printf "Checking environment variables...\n"
	@if [ -z "$(PRIVATE_KEY)" ]; then printf "$${COLOR_YELLOW}  WARNING: PRIVATE_KEY not set$${COLOR_RESET}\n"; fi
	@if [ -z "$(DAO_ADDRESS)" ]; then printf "$${COLOR_YELLOW}⚠️  WARNING: DAO_ADDRESS not set$${COLOR_RESET}\n"; fi
	@if [ -z "$(ADMIN_PLUGIN_ADDRESS)" ]; then printf "$${COLOR_YELLOW}⚠️  WARNING: ADMIN_PLUGIN_ADDRESS not set$${COLOR_RESET}\n"; fi
	@if [ -z "$(CAPITAL_DISTRIBUTOR_ADDRESS)" ]; then printf "$${COLOR_YELLOW}⚠️  WARNING: CAPITAL_DISTRIBUTOR_ADDRESS not set$${COLOR_RESET}\n"; fi
	@printf "$${COLOR_GREEN}✓ Environment check complete$${COLOR_RESET}\n"

# ===== Development Utilities =====

.PHONY: build
build: ## Build contracts
	@echo "Building contracts..."
	@forge build

.PHONY: test
test: ## Run tests
	@echo "Running tests..."
	@forge test -vvv

.PHONY: coverage
coverage: ## Run test coverage
	@echo "Running coverage..."
	@forge coverage

# ===== Merkle Tree Generation =====

.PHONY: generate-merkle-tree
generate-merkle-tree: ## Generate merkle tree from recipients file
	@echo "Generating merkle tree from ./script/fixtures/reciepients.json"
	@forge script script/utils/GenerateMerkleTree.s.sol:GenerateMerkleTree \
		"./script/fixtures/reciepients.json"

.PHONY: generate-merkle-proof
generate-merkle-proof: ## Generate merkle proof from merkle tree file
	@echo "Generating merkle proof from ./script/fixtures/merkle-tree.json"
	@forge script script/utils/GenerateProof.s.sol:GenerateProof

# Default target
.DEFAULT_GOAL := help

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Environment under envs/ (override with: make plan ENV=staging)
ENV         ?= demo
TF          ?= terraform
ENV_DIR     := envs/$(ENV)
# Layers in apply order (destroy runs in reverse). Each is its own root module and state.
LAYERS      := network compute workloads edge
# Layer for the single-layer targets: make plan LAYER=network
LAYER       ?=
LAYER_DIR   := $(ENV_DIR)/$(LAYER)
BOOT_DIR    := bootstrap
GITHUB_REPO ?=
# Only for repos with immutable OIDC subject claims, e.g. repo:owner@123/name@456
OIDC_SUB_PREFIX ?=

.PHONY: help bootstrap fmt fmt-check init validate lint plan apply destroy apply-all destroy-all output clean check-layer

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## One-time: create state bucket + CI roles (make bootstrap GITHUB_REPO=owner/repo)
	@test -n "$(GITHUB_REPO)" || { echo "Usage: make bootstrap GITHUB_REPO=owner/repo"; exit 1; }
	$(TF) -chdir=$(BOOT_DIR) init
	$(TF) -chdir=$(BOOT_DIR) apply -var="github_repo=$(GITHUB_REPO)" $(if $(OIDC_SUB_PREFIX),-var="github_oidc_subject_prefix=$(OIDC_SUB_PREFIX)")

fmt: ## Format all Terraform files
	$(TF) fmt -recursive

fmt-check: ## Check formatting (same as CI)
	$(TF) fmt -check -recursive

check-layer:
	@test -n "$(LAYER)" || { echo "Usage: make <target> LAYER=<$(LAYERS)>"; exit 1; }
	@test -d "$(LAYER_DIR)" || { echo "Unknown layer: $(LAYER)"; exit 1; }

init: check-layer ## Initialize one layer (LAYER=network)
	$(TF) -chdir=$(LAYER_DIR) init

validate: ## Validate every layer without touching the backend
	@for l in $(LAYERS); do \
		echo "==> $$l"; \
		$(TF) -chdir=$(ENV_DIR)/$$l init -backend=false -input=false >/dev/null && \
		$(TF) -chdir=$(ENV_DIR)/$$l validate || exit 1; \
	done

lint: ## Run tflint on all modules
	tflint --init
	tflint --recursive

plan: init ## Create an execution plan for one layer (saved as tfplan)
	$(TF) -chdir=$(LAYER_DIR) plan -out=tfplan

apply: plan ## Apply the saved plan of one layer
	$(TF) -chdir=$(LAYER_DIR) apply tfplan

destroy: init ## Destroy one layer (asks for confirmation)
	$(TF) -chdir=$(LAYER_DIR) destroy

apply-all: ## Apply every layer in order (network first)
	@for l in $(LAYERS); do $(MAKE) apply LAYER=$$l || exit 1; done

destroy-all: ## Destroy every layer in reverse order (edge first); asks per layer
	@for l in $(shell echo $(LAYERS) | tr ' ' '\n' | tac | tr '\n' ' '); do $(MAKE) destroy LAYER=$$l || exit 1; done

output: check-layer ## Show the outputs of one layer (LAYER=edge for the demo URLs)
	$(TF) -chdir=$(LAYER_DIR) output

clean: ## Remove local caches and saved plans
	find . -type d -name .terraform -prune -exec rm -rf {} +
	find $(ENV_DIR) -name 'tfplan*' -type f -delete

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Environment = a folder under envs/ with a values.yaml (override with: make plan ENV=staging).
# The Terraform code of the layers is shared by all environments (layers/).
ENV         ?= demo
# Every Terraform call for a layer goes through scripts/tf.sh (backend + environment)
TF          ?= terraform
TFL         := scripts/tf.sh $(ENV)
# Python for the values.yaml checks (needs scripts/requirements.txt)
PYTHON      ?= python3
# Layers in apply order (destroy runs in reverse). Each is its own root module and state.
LAYERS      := network compute workloads edge
# Layer for the single-layer targets: make plan LAYER=network
LAYER       ?=
LAYER_DIR   := layers/$(LAYER)
# The layers that read what a layer publishes, in apply order. `make apply` continues with them, because a
# change has to reach them (an EC2 instance that is replaced gets a new address, and edge must follow).
DOWNSTREAM_network   := compute workloads edge
DOWNSTREAM_compute   := workloads edge
DOWNSTREAM_workloads :=
DOWNSTREAM_edge      :=
# make apply LAYER=compute ONLY=1 applies just that layer
ONLY        ?=
BOOT_DIR    := bootstrap
GITHUB_REPO ?=
# Only for repos with immutable OIDC subject claims, e.g. repo:owner@123/name@456
OIDC_SUB_PREFIX ?=

.PHONY: help bootstrap fmt fmt-check init validate-values test-schemas test-modules test-scripts check-docs validate lint plan apply destroy apply-all destroy-all output clean check-layer

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
	$(TFL) $(LAYER) init

validate-values: ## Check every envs/*/values.yaml and the EC2 templates against their JSON Schema
	$(PYTHON) scripts/validate-values.py

test-schemas: ## Run the schema fixtures in schemas/tests
	PYTHON=$(PYTHON) bash scripts/test-schemas.sh

test-modules: ## Run the terraform tests of the modules that have them (modules/*/tests)
	@for d in modules/*/tests; do \
		m=$$(dirname $$d); \
		echo "==> $$m"; \
		$(TF) -chdir=$$m init -input=false >/dev/null && \
		$(TF) -chdir=$$m test || exit 1; \
	done

test-scripts: ## Test scripts/tf.sh and scripts/prepare-platform.sh (platform_version) with a fake terraform
	bash scripts/test-platform-pin.sh

check-docs: ## Check the links of README.md and docs/*.md (files and #anchors)
	python3 scripts/check-docs.py

validate: validate-values test-modules test-scripts check-docs ## Check values.yaml, the module tests and the docs, then validate every layer (no backend)
	@for l in $(LAYERS); do \
		echo "==> $$l"; \
		$(TFL) $$l init -backend=false -input=false >/dev/null && \
		$(TFL) $$l validate || exit 1; \
	done

lint: ## Run tflint on all modules
	tflint --init
	tflint --recursive

plan: init ## Create an execution plan for one layer (saved as tfplan)
	$(TFL) $(LAYER) plan -out=tfplan

apply: check-layer ## Apply a layer, then every layer after it (ONLY=1: just this layer)
	@for l in $(LAYER) $(if $(ONLY),,$(DOWNSTREAM_$(LAYER))); do \
		echo "==> apply $$l"; \
		$(TFL) $$l init -input=false >/dev/null && \
		$(TFL) $$l plan -out=tfplan && \
		$(TFL) $$l apply tfplan || exit 1; \
	done

destroy: init ## Destroy one layer (asks for confirmation)
	$(TFL) $(LAYER) destroy

apply-all: ## Apply every layer in order (network first)
	@$(MAKE) apply LAYER=network

destroy-all: ## Destroy every layer in reverse order (edge first); asks per layer
	@for l in $(shell echo $(LAYERS) | tr ' ' '\n' | tac | tr '\n' ' '); do $(MAKE) destroy LAYER=$$l || exit 1; done

output: check-layer ## Show the outputs of one layer (LAYER=edge for the demo URLs)
	$(TFL) $(LAYER) output

clean: ## Remove local caches and saved plans
	rm -rf .terraform-data
	find . -type d -name .terraform -prune -exec rm -rf {} +
	find layers -name 'tfplan*' -type f -delete

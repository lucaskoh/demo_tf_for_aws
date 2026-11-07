SHELL := /bin/bash
.DEFAULT_GOAL := help

# Environment under envs/ (override with: make plan ENV=staging)
ENV         ?= demo
TF          ?= terraform
ENV_DIR     := envs/$(ENV)
BOOT_DIR    := bootstrap
GITHUB_REPO ?=
# Only for repos with immutable OIDC subject claims, e.g. repo:owner@123/name@456
OIDC_SUB_PREFIX ?=

.PHONY: help bootstrap fmt fmt-check init validate lint plan apply destroy output clean

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

init: ## Initialize the environment (ENV=demo)
	$(TF) -chdir=$(ENV_DIR) init

validate: ## Validate the environment without touching the backend
	$(TF) -chdir=$(ENV_DIR) init -backend=false -input=false
	$(TF) -chdir=$(ENV_DIR) validate

lint: ## Run tflint on all modules
	tflint --init
	tflint --recursive

plan: init ## Create an execution plan (saved as tfplan)
	$(TF) -chdir=$(ENV_DIR) plan -out=tfplan

apply: plan ## Apply the saved plan
	$(TF) -chdir=$(ENV_DIR) apply tfplan

destroy: init ## Destroy the environment (asks for confirmation)
	$(TF) -chdir=$(ENV_DIR) destroy

output: ## Show outputs (demo URLs)
	$(TF) -chdir=$(ENV_DIR) output

clean: ## Remove local caches and saved plans
	find . -type d -name .terraform -prune -exec rm -rf {} +
	rm -f $(ENV_DIR)/tfplan $(ENV_DIR)/tfplan-destroy
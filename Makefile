.PHONY: help prereqs kind-up kind-down build-image verify baseline reset add-extension database load diff-extension smoke teardown setup setup-kind show-baseline show-wiring show-metric

SHELL := /bin/bash

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

prereqs: ## Check required tools
	@scripts/00-prereqs-check.sh

kind-up: ## Create kind, install CNPG and Prometheus, verify
	@scripts/kind/01-create.sh && scripts/kind/02-install-cnpg.sh && scripts/kind/03-install-prometheus.sh && scripts/kind/check.sh

kind-down: ## Delete the kind cluster
	@kind delete cluster --name $${KIND_CLUSTER:-cnpg-imgvol}; rm -f .ext-image.env

build-image: ## Build the extension image and make it reachable from the cluster
	@scripts/10-build-extension-image.sh

verify: ## Check preconditions on the current context
	@scripts/20-verify.sh

baseline: ## Deploy the cluster without the extension
	@scripts/30-deploy-baseline.sh

reset: ## Back to the baseline (removes the demo cluster and Database, keeps the image)
	@scripts/80-reset.sh

add-extension: ## Add the extension (rolling update)
	@scripts/40-add-extension.sh

database: ## Create the extension through the Database resource
	@scripts/50-create-database.sh

load: ## Run a small SQL load
	@scripts/60-load.sh

diff-extension: ## Show the YAML diff between baseline and extension
	@source scripts/_env.sh; ROOT=$$PWD; load_ext_image 2>/dev/null || EXT_IMAGE='<extension image>'; \
	  diff -u <(render manifests/cnpg/cluster-baseline.yaml) <(render manifests/cnpg/cluster-extension.yaml) || true

smoke: ## End-to-end check of the whole demo on the current context
	@scripts/smoke.sh

teardown: ## Delete the demo namespace (only if it is ours)
	@scripts/teardown.sh

setup: ## Existing cluster: build image, verify, deploy the baseline
	@scripts/10-build-extension-image.sh && scripts/20-verify.sh && scripts/30-deploy-baseline.sh

setup-kind: kind-up setup ## kind: create the cluster, then setup

show-baseline: ## Show CREATE EXTENSION failing on the baseline
	@scripts/70-show.sh baseline

show-wiring: ## Show the mount and the settings that point at it
	@scripts/70-show.sh wiring

show-metric: ## Show the custom metric as Prometheus sees it
	@scripts/70-show.sh metric

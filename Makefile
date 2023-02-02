CHART_OPTS=-f values-secret.yaml.template -f values-global.yaml -f values-hub.yaml --set global.targetRevision=main --set global.valuesDirectoryURL="https://github.com/hybrid-cloud-patterns/ansible-edge-gitops/raw/main/" --set global.pattern="$(NAME)" --set global.namespace="$(NAME)" --set global.hubClusterDomain=example.com --set global.localClusterDomain=local.example.com
PATTERN_OPTS=-f common/examples/values-example.yaml

.PHONY: default
default: help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^(\s|[a-zA-Z_0-9-])+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

%:
	make -f common/Makefile $*

install upgrade deploy: operator-deploy post-install ## Install or upgrade the pattern via the operator
	echo "Installed/Upgraded"

post-install: ## Post-install tasks - load-secrets
	make load-secrets
	echo "Post-deploy complete"

deploy-kubevirt-worker: ## Deploy the metal node worker (from workstation). This is normally done in-cluster
	./scripts/deploy_kubevirt_worker.sh

configure-controller: ## Configure AAP operator (from workstation). This is normally done in-cluster
	ansible-playbook ./scripts/ansible_load_controller.sh -e "aeg_project_repo=$(TARGET_REPO) aeg_project_branch=$(TARGET_BRANCH)"

test: ## Run tests
	make -f common/Makefile PATTERN_OPTS="$(CHART_OPTS)" test
	echo Tests SUCCESSFUL

update-tests: ## Update test results
	./scripts/update-tests.sh $(CHART_OPTS)

.phony: install test

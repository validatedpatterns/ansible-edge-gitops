CHART_OPTS=-f values-secret.yaml.template -f values-global.yaml -f values-hub.yaml --set global.targetRevision=main --set global.valuesDirectoryURL="https://github.com/hybrid-cloud-patterns/ansible-edge-gitops/raw/main/" --set global.pattern="$(NAME)" --set global.namespace="$(NAME)" --set global.hubClusterDomain=example.com --set global.localClusterDomain=local.example.com
PATTERN_OPTS=-f common/examples/values-example.yaml

.PHONY: default
default: help

help:
	@make -f common/Makefile MAKEFILE_LIST="Makefile common/Makefile" help

%:
	make -f common/Makefile $*

install upgrade deploy: operator-deploy post-install ## Install or upgrade the pattern via the operator
	echo "Installed/Upgraded"

portworx-install portworx-upgrade portworx-deploy: ## Install with portworx instead
	EXTRA_HELM_OPTS='-f values-portworx.yaml' make install

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

portworx-test:
	EXTRA_HELM_OPTS='-f values-portworx.yaml' make test

update-tests: ## Update test results
	./scripts/update-tests.sh $(CHART_OPTS)

.phony: install test

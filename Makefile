CHART_OPTS=-f values-secret.yaml.template -f values-global.yaml -f values-hub.yaml --set global.targetRevision=main --set global.valuesDirectoryURL="https://github.com/hybrid-cloud-patterns/ansible-edge-gitops/raw/main/" --set global.pattern="$(NAME)" --set global.namespace="$(NAME)" --set global.hubClusterDomain=example.com --set global.localClusterDomain=local.example.com
PATTERN_OPTS=-f common/examples/values-example.yaml

.PHONY: default
default: help

# No need to add a comment here as help is described in common/
help:
	@printf "$$(grep -hE '^\S.*:.*##' $(MAKEFILE_LIST) common/Makefile | sort | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)\n"

%:
	make -f common/Makefile $*

install upgrade deploy: operator-deploy post-install ## Install or upgrade the pattern via the operator
	echo "Installed/Upgraded"

legacy-install legacy-upgrade: legacy-deploy post-install ## Install or upgrade the pattern the "old" way
	echo "Installed/upgraded (Legacy target)"

post-install: ## Post-install tasks - vault, configure_controller
	@if grep -v -e '^\s\+#' "values-hub.yaml" | grep -q -e "insecureUnsealVaultInsideCluster:\s\+true"; then \
      echo "Skipping 'make vault-init' as we're unsealing the vault from inside the cluster"; \
    else \
      make vault-init; \
    fi
	make load-secrets
	echo "Post-deploy complete"

deploy-kubevirt-worker: ## Deploy the metal node worker
	./scripts/deploy_kubevirt_worker.sh

configure-controller: ## Configure AAP operator
	ansible-playbook ./scripts/ansible_load_controller.sh -e "aeg_project_repo=$(TARGET_REPO) aeg_project_branch=$(TARGET_BRANCH)"

test: ## Run tests
	make -f common/Makefile PATTERN_OPTS="$(CHART_OPTS)" test
	echo Tests SUCCESSFUL

update-tests:
	./scripts/update-tests.sh $(CHART_OPTS)

.phony: install test

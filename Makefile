NAME=ansible-edge-gitops
PATTERN=ansible-edge-gitops
TARGET_BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
HUBCLUSTER_APPS_DOMAIN=$(shell oc get ingresses.config/cluster -o jsonpath={.spec.domain})
TARGET_REPO=$(shell git remote show origin | grep Push | sed -e 's/.*URL:[[:space:]]*//' -e 's%^git@%%' -e 's%^https://%%' -e 's%:%/%' -e 's%^%https://%')
CHART_OPTS=-f values-secret.yaml.template -f values-global.yaml -f values-hub.yaml --set global.targetRevision=main --set global.valuesDirectoryURL="https://github.com/hybrid-cloud-patterns/ansible-edge-gitops/raw/main/" --set global.pattern="$(NAME)" --set global.namespace="$(NAME)" --set global.hubClusterDomain=example.com --set global.localClusterDomain=local.example.com
HELM_OPTS=-f values-global.yaml -f values-hub.yaml --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) --set global.hubClusterDomain=$(HUBCLUSTER_APPS_DOMAIN) --set global.localClusterDomain=$(HUBCLUSTER_APPS_DOMAIN)

.PHONY: default
default: help

# --set values always take precedence over the contents of -f
HELM_OPTS=-f values-global.yaml --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) \
	--set global.hubClusterDomain=$(HUBCLUSTER_APPS_DOMAIN)
TEST_OPTS= -f common/examples/values-secret.yaml -f values-global.yaml --set global.repoURL="https://github.com/pattern-clone/mypattern" \
	--set main.git.repoURL="https://github.com/pattern-clone/mypattern" --set main.git.revision=main --set global.pattern="mypattern" \
	--set global.namespace="pattern-namespace" --set global.hubClusterDomain=hub.example.com --set global.localClusterDomain=region.example.com \
	--set "clusterGroup.imperative.jobs[0].name"="test" --set "clusterGroup.imperative.jobs[0].playbook"="ansible/test.yml" \
	--set clusterGroup.insecureUnsealVaultInsideCluster=true
PATTERN_OPTS=-f common/examples/values-example.yaml
EXECUTABLES=git helm oc ansible

.PHONY: help
# No need to add a comment here as help is described in common/
help:
	@printf "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) common/Makefile | sort | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)\n"

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

common-test: ## Test common
	make -C common -f common/Makefile test

test: ## Run tests
	make ansible-lint
	make -f common/Makefile -C common test
	make -f common/Makefile CHARTS="$(wildcard charts/hub/*)" PATTERN_OPTS="$(CHART_OPTS)" test
	echo Tests SUCCESSFUL

helmlint:
	# no regional charts just yet: "$(wildcard charts/region/*)"
	@for t in "$(wildcard charts/hub/*)"; do helm lint $$t; if [ $$? != 0 ]; then exit 1; fi; done

super-linter: ## Runs super linter locally
	make -f common/Makefile DISABLE_LINTERS="-e VALIDATE_ANSIBLE=false -e VALIDATE_DOCKERFILE_HADOLINT=false" super-linter

update-tests:
	./scripts/update-tests.sh $(CHART_OPTS)

uninstall: ## runs helm uninstall
	helm uninstall $(NAME)

vault-init: ## inits, unseals and configured the vault
	common/scripts/vault-utils.sh vault_init common/pattern-vault.init
	common/scripts/vault-utils.sh vault_unseal common/pattern-vault.init
	common/scripts/vault-utils.sh vault_secrets_init common/pattern-vault.init

vault-unseal: ## unseals the vault
	common/scripts/vault-utils.sh vault_unseal common/pattern-vault.init

load-secrets: ## loads the secrets into the vault
	common/scripts/vault-utils.sh push_secrets common/pattern-vault.init

super-linter: ## Runs super linter locally
	podman run -e RUN_LOCAL=true -e USE_FIND_ALGORITHM=true	\
					-e VALIDATE_BASH=false \
					-e VALIDATE_JSCPD=false \
					-e VALIDATE_KUBERNETES_KUBEVAL=false \
					-e VALIDATE_YAML=false \
					$(DISABLE_LINTERS) \
					-v $(PWD):/tmp/lint:rw,z docker.io/github/super-linter:slim-v4

ansible-lint: ## run ansible lint on ansible/ folder
	podman run -it -v $(PWD):/workspace:rw,z --workdir /workspace --entrypoint "/usr/local/bin/ansible-lint" quay.io/ansible/creator-ee:latest  "-vvv" "ansible/"

.phony: install test

NAME=ansible-edge-gitops
PATTERN=ansible-edge-gitops
TARGET_BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
HUBCLUSTER_APPS_DOMAIN=$(shell oc get ingresses.config/cluster -o jsonpath={.spec.domain})
TARGET_REPO=$(shell git remote show origin | grep Push | sed -e 's/.*URL:[[:space:]]*//' -e 's%^git@%%' -e 's%^https://%%' -e 's%:%/%' -e 's%^%https://%')
CHART_OPTS=-f values-secret.yaml.template -f values-global.yaml -f values-hub.yaml --set global.targetRevision=main --set global.valuesDirectoryURL="https://github.com/hybrid-cloud-patterns/ansible-edge-gitops/raw/main/" --set global.pattern="$(NAME)" --set global.namespace="$(NAME)" --set global.hubClusterDomain=example.com --set global.localClusterDomain=local.example.com
HELM_OPTS=-f values-global.yaml -f values-hub.yaml --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) --set global.hubClusterDomain=$(HUBCLUSTER_APPS_DOMAIN) --set global.localClusterDomain=$(HUBCLUSTER_APPS_DOMAIN)
BOOTSTRAP=1

.PHONY: default
default: help

.PHONY: help
# No need to add a comment here as help is described in common/
help:
	@printf "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) common/Makefile | sort | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)\n"

%:
	make -f common/Makefile $*

install: operator-deploy ## installs the pattern, inits the vault and loads the secrets
	make vault-init
	make load-secrets
	./scripts/deploy_kubevirt_worker.sh
	ansible-playbook ./scripts/ansible_load_controller.sh -e "aeg_project_repo=$(TARGET_REPO) aeg_project_branch=$(TARGET_BRANCH)"
	echo "Installed"

upgrade: operator-deploy
	make vault-init
	make load-secrets
	./scripts/deploy_kubevirt_worker.sh
	ansible-playbook ./scripts/ansible_load_controller.sh -e "aeg_project_repo=$(TARGET_REPO) aeg_project_branch=$(TARGET_BRANCH)"
	echo "Upgraded"

legacy-install legacy-upgrade: legacy-deploy
	make vault-init
	make load-secrets
	./scripts/deploy_kubevirt_worker.sh
	ansible-playbook ./scripts/ansible_load_controller.sh -e "aeg_project_repo=$(TARGET_REPO) aeg_project_branch=$(TARGET_BRANCH)"
	echo "Installed/upgraded"

common-test:
	make -C common -f common/Makefile test


test:
	make ansible-lint
	make -f common/Makefile -C common test
	make -f common/Makefile CHARTS="$(wildcard charts/hub/*)" PATTERN_OPTS="$(CHART_OPTS)" test
	echo Tests SUCCESSFUL

validate-origin: ## verify the git origin is available
	@echo Checking repo $(TARGET_REPO) - branch $(TARGET_BRANCH)
	@git ls-remote --exit-code --heads $(TARGET_REPO) $(TARGET_BRANCH) >/dev/null && \
		echo "$(TARGET_REPO) - $(TARGET_BRANCH) exists" || \
		(echo "$(TARGET_BRANCH) not found in $(TARGET_REPO)"; exit 1)

helmlint:
	# no regional charts just yet: "$(wildcard charts/region/*)"
	@for t in "$(wildcard charts/hub/*)"; do helm lint $$t; if [ $$? != 0 ]; then exit 1; fi; done

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

super-linter: ## Runs super linter locally
	podman run -e RUN_LOCAL=true -e USE_FIND_ALGORITHM=true	\
					-e VALIDATE_BASH=false \
					-e VALIDATE_JSCPD=false \
					-e VALIDATE_KUBERNETES_KUBEVAL=false \
					-e VALIDATE_YAML=false \
					-e VALIDATE_DOCKERFILE_HADOLINT=false \
					-e VALIDATE_ANSIBLE=false \
					-v $(PWD):/tmp/lint:rw,z docker.io/github/super-linter:slim-v4

ansible-lint: ## run ansible lint on ansible/ folder
	podman run -it -v $(PWD):/workspace:rw,z --workdir /workspace --entrypoint "/usr/local/bin/ansible-lint" quay.io/ansible/creator-ee:latest  "-vvv" "ansible/"

.phony: install test

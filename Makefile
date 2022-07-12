NAME=ansible-edge-gitops
PATTERN=ansible-edge-gitops
TARGET_BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
HUBCLUSTER_APPS_DOMAIN=$(shell oc get ingresses.config/cluster -o jsonpath={.spec.domain})
TARGET_REPO=$(shell git remote show origin | grep Push | sed -e 's/.*URL:[[:space:]]*//' -e 's%^git@%%' -e 's%^https://%%' -e 's%:%/%' -e 's%^%https://%')
CHART_OPTS=-f values-secret.yaml.template -f values-global.yaml -f values-hub.yaml --set global.targetRevision=main --set global.valuesDirectoryURL="https://github.com/hybrid-cloud-patterns/ansible-edge-gitops/raw/main/" --set global.pattern="$(NAME)" --set global.namespace="$(NAME)" --set global.hubClusterDomain=example.com --set global.localClusterDomain=local.example.com
HELM_OPTS=-f values-global.yaml -f values-hub.yaml --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) --set global.hubClusterDomain=$(HUBCLUSTER_APPS_DOMAIN) --set global.localClusterDomain=$(HUBCLUSTER_APPS_DOMAIN)

.PHONY: default
default: help

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

post-install: vault-init deploy-kubevirt-worker configure-controller ## Post-install tasks - vault, kubevirt, controller config
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

update-tests:
	./scripts/update-tests.sh $(CHART_OPTS)

uninstall: ## runs helm uninstall
	helm uninstall $(NAME)

super-linter: ## Runs super linter locally
	podman run -e RUN_LOCAL=true -e USE_FIND_ALGORITHM=true	\
					-e VALIDATE_BASH=false \
					-e VALIDATE_JSCPD=false \
					-e VALIDATE_KUBERNETES_KUBEVAL=false \
					-e VALIDATE_YAML=false \
					-e VALIDATE_DOCKERFILE_HADOLINT=false \
					-e VALIDATE_ANSIBLE=false \
					-v $(PWD):/tmp/lint:rw,z docker.io/github/super-linter:slim-v4

.phony: install test

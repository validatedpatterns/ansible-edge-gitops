NAME=ansible-edge-gitops
PATTERN=ansible-edge-gitops
SECRETS=~/values-secret.yaml
TARGET_BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
HUBCLUSTER_APPS_DOMAIN=$(shell oc get ingresses.config/cluster -o jsonpath={.spec.domain})
TARGET_REPO=$(shell git remote show origin | grep Push | sed -e 's/.*URL:[[:space:]]*//' -e 's%^git@%%' -e 's%^https://%%' -e 's%:%/%' -e 's%^%https://%')
CHART_OPTS=-f values-secret.yaml.template -f values-global.yaml -f values-hub.yaml --set global.targetRevision=main --set global.valuesDirectoryURL="https://github.com/hybrid-cloud-patterns/ansible-edge-gitops/raw/main/" --set global.pattern="$(NAME)" --set global.namespace="$(NAME)" --set global.hubClusterDomain=example.com --set global.localClusterDomain=local.example.com
HELM_OPTS=-f values-global.yaml -f values-hub.yaml -f $(SECRETS) --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) --set global.hubClusterDomain=$(HUBCLUSTER_APPS_DOMAIN) --set global.localClusterDomain=$(HUBCLUSTER_APPS_DOMAIN)
BOOTSTRAP=1

.PHONY: default
default: help

.PHONY: help
# No need to add a comment here as help is described in common/
help:
	@printf "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) common/Makefile | sort | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)\n"

%:
	make -f common/Makefile $*

install: deploy ## installs the pattern, inits the vault and loads the secrets
	make vault-init
	./scripts/deploy_kubevirt_worker.sh
	./scripts/ansible_load_controller.sh
	echo "Installed"

common-test:
	make -C common -f common/Makefile test

test:
	make -f common/Makefile CHARTS="$(wildcard charts/hub/*)" PATTERN_OPTS="$(CHART_OPTS)" test

helmlint:
	# no regional charts just yet: "$(wildcard charts/region/*)"
	@for t in "$(wildcard charts/hub/*)"; do helm lint $$t; if [ $$? != 0 ]; then exit 1; fi; done

update-tests:
	./scripts/update-tests.sh $(CHART_OPTS)

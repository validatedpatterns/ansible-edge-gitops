include Makefile-common

.PHONY: default
default: help

deploy-kubevirt-worker: ## Deploy the metal node worker (from workstation). This is normally done in-cluster
	./scripts/deploy_kubevirt_worker.sh

configure-controller: ## Configure AAP operator (from workstation). This is normally done in-cluster
	ansible-playbook ./scripts/ansible_load_controller.sh -e "aeg_project_repo=$(TARGET_REPO) aeg_project_branch=$(TARGET_BRANCH)"

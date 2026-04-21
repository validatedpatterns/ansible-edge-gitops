include Makefile-common

##@ Pattern Install Helper Tasks
.PHONY: ansible-get-credentials
ansible-get-credentials: ## Retrieve AAP credentials from running instance
	@$(ANSIBLE_RUN) rhvp.cluster_utils.aap_get_admin_credentials

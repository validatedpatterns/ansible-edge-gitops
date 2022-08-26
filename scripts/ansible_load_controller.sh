#!/usr/bin/env ansible-playbook
---
- name: Retrieve AAP credentials
  ansible.builtin.import_playbook: ../ansible/ansible_get_credentials.yml

- name: Parse secrets from local values_secret.yaml file
  ansible.builtin.import_playbook: ../parse_secrets_from_values_secret.yml

- name: Configure AAP instance
  ansible.builtin.import_playbook: ../ansible/ansible_configure_controller.yml

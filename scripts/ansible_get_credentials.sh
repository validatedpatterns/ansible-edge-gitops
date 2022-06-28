#!/usr/bin/env ansible-playbook
---
- name: Retrieve AAP credentials
  ansible.builtin.import_playbook: ../ansible/ansible_get_credentials.yml

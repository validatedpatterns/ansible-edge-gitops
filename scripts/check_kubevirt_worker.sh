#!/usr/bin/env ansible-playbook
---
- name: Check on Kubevirt Worker Status
  ansible.builtin.import_playbook: ../ansible/check_kubevirt_worker.yml

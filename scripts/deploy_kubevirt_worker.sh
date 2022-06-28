#!/usr/bin/env ansible-playbook
---
- name: Deploy KubeVirt Worker
  ansible.builtin.import_playbook: ../ansible/deploy_kubevirt_worker.yml

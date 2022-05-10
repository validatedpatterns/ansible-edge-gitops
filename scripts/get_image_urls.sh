#!/usr/bin/env ansible-playbook
---
- name: "Retrieve RHEL image(s)"
  become: false
  connection: local
  hosts: localhost
  gather_facts: false
  vars:
    kubeconfig: "{{ lookup('env', 'KUBECONFIG') }}"
    refresh_token_file: "{{ lookup('env', 'REFRESH_TOKEN_FILE') }}"
    refresh_token_contents: "{{ lookup('file', refresh_token_file) }}"
    redhat_sso_url: 'https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token'
    redhat_api_url: https://api.access.redhat.com/management/v1
    image_checksums:
      # rhel-8.5-x86_64-kvm.qcow2
      - "9b63267716fa557f76df4899fb6a591c4c8a6ae2828f6297458815bff55ce8cc"
      # rhel-8.5-x86_64-boot.iso
      - "61fe463758f6ee9b21c4d6698671980829ca4f747a066d556fa0e5eefc45382c"
    initial_download_path: /tmp
  tasks:
    - name: "Debug vars"
      ansible.builtin.debug:
        msg: '{{ refresh_token_file }} {{ refresh_token_contents }}'

    - name: Generate Access Token
      ansible.builtin.uri:
        body:
          client_id: rhsm-api
          grant_type: refresh_token
          refresh_token: "{{ refresh_token_contents }}"
        body_format: form-urlencoded
        method: POST
        url: "{{ redhat_sso_url }}"
      register: access_token

    - name: Generate Image Download URLs
      ansible.builtin.uri:
        follow_redirects: none
        headers:
          Authorization: "Bearer {{ access_token.json.access_token }}"
        status_code: 307
        url: "{{ redhat_api_url }}/images/{{ item }}/download"
      register: image_urls
      loop: "{{ image_checksums }}"

    - name: Download Red Hat Images
      ansible.builtin.get_url:
        checksum: "sha256:{{ item.item }}"
        dest: "{{ initial_download_path }}/{{ item.json.body.filename }}"
        url: "{{ item.json.body.href }}"
      loop: "{{ image_urls.results }}"

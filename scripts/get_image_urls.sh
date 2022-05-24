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
      #- "9b63267716fa557f76df4899fb6a591c4c8a6ae2828f6297458815bff55ce8cc"
      # rhel-8.5-x86_64-boot.iso
      #- "61fe463758f6ee9b21c4d6698671980829ca4f747a066d556fa0e5eefc45382c"
      # rhel-8.6-x86_64-kvm.qcow2
      - "c9b32bef88d605d754b932aad0140e1955ab9446818c70c4c36ca75d6f442fe9"
      # rhel-8.6-x86_64-boot.iso
      - "4a3ffcec86ba40c89fc2608c8e3bb00b71d572da219f30904536cdce80b58e76"
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

    - name: Get route for upload proxy
      kubernetes.core.k8s_info:
        kind: Route
        namespace: openshift-cnv
        name: cdi-uploadproxy
      register: uploadproxy_route

    - name: "Set host variable"
      ansible.builtin.set_fact:
        uploadproxy_url: 'https://{{ uploadproxy_route.resources[0].spec.host }}'

    - name: "debug host variable"
      ansible.builtin.debug:
        msg: '{{ uploadproxy_url }}'

    - name: Upload images to CDI proxy
      community.kubevirt.kubevirt_cdi_upload:
        pvc_namespace: default
        pvc_name: 'pvc-{{ item.json.body.filename }}'
        upload_host_validate_certs: false
        upload_host: '{{ uploadproxy_url }}'
        dest: "{{ initial_download_path }}/{{ item.json.body.filename }}"
      loop: "{{ image_urls.results }}"

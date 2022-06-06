#!/usr/bin/env ansible-playbook
---
- name: "Install manifest on AAP controller"
  become: false
  connection: local
  hosts: localhost
  gather_facts: false
  vars:
    values_secret: "{{ lookup('env', 'HOME') }}/values-secret.yaml"
    kubeconfig: "{{ lookup('env', 'KUBECONFIG') }}"
    aap_org_name: "HMI Demo"
    aap_execution_environment: "Ansible Edge Gitops EE"
    aap_execution_environment_image: "quay.io/martjack/ansible-edge-gitops-ee"
  tasks:
    - name: Parse "{{ values_secret }}"
      ansible.builtin.set_fact:
        all_values: "{{ lookup('file', values_secret) | from_yaml }}"

    - name: Set files fact
      ansible.builtin.set_fact:
        manifest_file_ref: "{{ all_values['files']['manifest'] }}"

    - name: Load manifest into variable
      local_action:
        module: slurp
        src: '{{ manifest_file_ref }}'
      register: manifest_file
      become: false

    #- name: Wait for 5 minutes to ensure controller install completes
    #  ansible.builtin.pause:
    #    minutes: 5

    - name: Get web pod name
      retries: 60
      delay: 10
      kubernetes.core.k8s_info:
        kind: pod
        namespace: ansible-automation-platform
        label_selectors:
          - 'app.kubernetes.io/name = controller'
      register: aappods
      until: aappods.resources | length >= 1

    - name: Sed podname fact
      ansible.builtin.set_fact:
        webpodname: '{{ aappods.resources[0].metadata.name }}'

    - name: Ensure migrations are done
      kubernetes.core.k8s_exec:
        namespace: 'ansible-automation-platform'
        pod: '{{ webpodname }}'
        container: controller-web
        command: 'bash -c "awx-manage migrate || /usr/bin/wait-for-migrations"'
      register: awx_status
      retries: 60
      delay: 10
      until: awx_status is not failed
      changed_when: false

    - name: Wait for API/UI route to deploy
      kubernetes.core.k8s_info:
        kind: Route
        namespace: ansible-automation-platform
        name: controller
      register: aap_host
      retries: 20
      delay: 5
      until: aap_host.resources | length > 0

    - name: Retrieve API hostname for AAP
      kubernetes.core.k8s_info:
        kind: Route
        namespace: ansible-automation-platform
        name: controller
      register: aap_host
      failed_when: aap_host.resources | length == 0

    - name: Set ansible_host
      set_fact:
        ansible_host: '{{ aap_host.resources[0].spec.host }}'

    - name: Retrieve admin password for AAP
      kubernetes.core.k8s_info:
        kind: Secret
        namespace: ansible-automation-platform
        name: controller-admin-password
      register: admin_pw
      failed_when: admin_pw.resources | length == 0

    - name: Set admin_password fact
      set_fact:
        admin_password: '{{ admin_pw.resources[0].data.password | b64decode }}'

    - name: Wait for API to become available
      retries: 20
      delay: 5
      register: api_status
      until: api_status.status == 200
      uri:
        url: https://{{ ansible_host }}/api/v2/config/
        method: GET
        user: admin
        password: "{{admin_password}}"
        body_format: json
        validate_certs: false
        force_basic_auth: true
      no_log: true

    - name: Load license the awx way
      awx.awx.license:
        controller_host: '{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        manifest: '{{ manifest_file_ref }}'
        validate_certs: false
      retries: 30
      delay: 10
      register: result
      until: result is not failed

    - name: Report AAP Endpoint
      debug:
        msg: 'AAP Endpoint: https://{{ ansible_host }}'

    - name: Report AAP User
      debug:
        msg: 'AAP Admin User: admin'

    - name: Report AAP Admin Password
      debug:
        msg: 'AAP Admin Password: {{ admin_password }}'

    # Add a user
    # Add an organization
    # Add an inventory
    # Add a credential
    # Project
    # Job Templates

    - name: Configure Credential Types
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.credential_types
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_configuration_async_retries: 10
        controller_credential_types:
          - name: Kubeconfig
            description: kubeconfig file
            kind: "cloud"
            inputs:
              fields:
                - id: kube_config
                  type: string
                  label: kubeconfig
                  secret: true
                  multiline: true
              required:
                - kube_config
            injectors:
              env:
                K8S_AUTH_KUBECONFIG: "{  { tower.filename.kubeconfig }}"
              file:
                template.kubeconfig: "{  { kube_config }}"

    - name: Configure Organizations
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.organizations
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_configuration_async_retries: 10
        controller_organizations:
          - name: '{{ aap_org_name }}'

    - name: Configure Projects
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.projects
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_projects:
          - name: "Demo Project"
            state: absent

          - name: "AEG GitOps"
            organization: '{{ aap_org_name }}'
            scm_branch: 'main'
            scm_clean: "no"
            scm_delete_on_update: "no"
            scm_type: "git"
            scm_update_on_launch: "yes"
            scm_url: "https://github.com/mhjacks/ansible-edge-gitops.git"

          - name: "HMI Demo"
            organization: '{{ aap_org_name }}'
            scm_branch: 'main'
            scm_clean: "no"
            scm_delete_on_update: "no"
            scm_type: "git"
            scm_update_on_launch: "no"
            scm_url: "https://github.com/stolostron/hmi-demo.git"

    - name: Debug kioskkey
      debug:
        msg: "{{ all_values['secrets']['kiosk-ssh']['privatekey'] }}"

    - name: Configure Kubernetes Credentials
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.credentials
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_configuration_async_retries: 10
        controller_credentials:
          - name: 'Kubeconfig'
            description: "Local Cluster Kubeconfig"
            organization: "{{ aap_org_name }}"
            credential_type: "Kubeconfig"
            inputs:
              kube_config: "{{ lookup('file', kubeconfig) }}"

    - name: Configure Machine Credentials
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.credentials
      loop:
        - kiosk
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_configuration_async_retries: 10
        controller_credentials:
          - name: '{{ item }}-private-key'
            description: "Machine credential for {{ item }} type machines"
            organization: "{{ aap_org_name }}"
            credential_type: Machine
            inputs:
              username: "{{ all_values['secrets'][item ~ '-ssh']['username']  }}"
              ssh_key_data: "{{ lookup('file', all_values['files'][item ~ '-ssh']['privatekey'])  }}"


    - name: Configure Inventories
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.inventories
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_inventories:
          - name: "HMI Demo"
            organization: "{{ aap_org_name }}"

          - name: "HMI Demo Kiosks"
            organization: "{{ aap_org_name }}"
            kind: smart
            host_filter: 'name__icontains=kiosk'

    - name: Configure Inventory Sources
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.inventory_sources
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_inventory_sources:
#          - name: "HMI Demo IDM Source"
#            organization: "{{ aap_org_name }}"
#            inventory: "HMI Demo"
#            credential: "Kubeconfig"
#            update_on_launch: true
#            source: "scm"
#            source_project: "AEG GitOps"
#            source_path: "ansible/inventory/openshift_cluster.yml"
#            host_filter: ".*idm.*service"
#
#          - name: "HMI Demo Kiosk Source"
#            organization: "{{ aap_org_name }}"
#            inventory: "HMI Demo"
#            credential: "Kubeconfig"
#            update_on_launch: true
#            source: "scm"
#            source_project: "AEG GitOps"
#            source_path: "ansible/inventory/openshift_cluster.yml"
#            host_filter: ".*kiosk.*service"

          - name: "HMI Demo Static Source"
            organization: "{{ aap_org_name }}"
            inventory: "HMI Demo"
            update_on_launch: true
            source: "scm"
            source_project: "AEG GitOps"
            source_path: "ansible/inventory/hosts"

    - name: Configure Execution Environments
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.execution_environments
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_execution_environments:
          - name: '{{ aap_execution_environment }}'
            image: '{{ aap_execution_environment_image }}'

    - name: Configure Job Templates
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.job_templates
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_templates:
          - name: "Demo Job Template"
            state: absent

          - name: "Ping Playbook"
            organization: '{{ aap_org_name }}'
            project: "AEG GitOps"
            job_type: run
            playbook: "ansible/playbooks/ping.yml"
            inventory: "HMI Demo"
            execution_environment: '{{ aap_execution_environment }}'

          - name: "Kiosk Playbook"
            organization: '{{ aap_org_name }}'
            project: "HMI Demo"
            job_type: run
            playbook: "ansible/kiosk_playbook.yml"
            inventory: "HMI Demo"
            execution_environment: '{{ aap_execution_environment }}'

          - name: "Podman Playbook"
            organization: '{{ aap_org_name }}'
            project: "HMI Demo"
            job_type: run
            playbook: "ansible/podman_playbook.yml"
            inventory: "HMI Demo"
            execution_environment: '{{ aap_execution_environment }}'

    - name: Configure Schedules
      ansible.builtin.include_role:
        name: redhat_cop.controller_configuration.schedules
      vars:
        controller_hostname: 'https://{{ ansible_host }}'
        controller_username: admin
        controller_password: '{{ admin_password }}'
        controller_validate_certs: false
        controller_schedules:
          - name: "Update Project HMI Demo"
            organization: '{{ aap_org_name }}'
            unified_job_template: "HMI Demo"
            rrule: "DTSTART:20191219T130551Z RRULE:FREQ=MINUTELY;INTERVAL=15"

          - name: "Update Project AEG GitOps"
            organization: '{{ aap_org_name }}'
            unified_job_template: "AEG GitOps"
            rrule: "DTSTART:20191219T130551Z RRULE:FREQ=MINUTELY;INTERVAL=5"

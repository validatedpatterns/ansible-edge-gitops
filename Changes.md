# Change history for significant pattern releases

## Changes for v1.1 (October 28, 2022)

* ODF improvements: Kiosk VMs now explicitly request ceph storage from ODF by in order to be live-migratable, in situations with multiple virt-capable workers. Storage types can be customized per-VM using the `storageClassName`, `volumeMode`, and `accessMode` attributes of a specific VM type, or by setting the `defaultStorageClass`, `defultAccessMode`, and `defaultAccessMode` values in the chart. The settings are `coalesce`'d in the chart template so you can mix and match as desired.

* edge-gitops-vms wait: edge-gitops-vms now waits until there is at least one metal node "ready" before creating the VM-related resources. This prevents the application from being marked as in "error" state due to potential repeated failures due to the kubevirt.io API not being available. This can be turned off by using the `.Values.waitForMetalNode` toggle in the `edge-gitops-vms` chart.

* More comprehensive use of (Hashicorp) Vault secrets: All secrets are now stored in Vault and published in the `aap-config` application so that playbooks can retrieve them and provide them to AAP.

* More declarative configuration: AAP configuration now runs as part of the imperative framework, so that changes to the `ansible_configure_controller.yml` playbook will be applied on future runs of the imperative job.

* Fix Out-of-Sync conditions: Fixed cosmetic issues in both the ODF (OpenShift Data Foundations) and CNV (OpenShift Virtualization/Container Native Virtualization) spaces that would make those applications show as out-of-sync. These issues caused our internal CI to fail and we judged it better to fix those issues than to "live" with the out-of-syncs.

## Changes for v1.2 (February 9, 2023)

* Kiosk_mode improvements: kiosk_mode role now has a variable `kiosk_port` which influences the kiosk-mode script and controls which port firefox connects to. (Previously this was hardcoded to port 8088; the var defaults to 8088 so existing setups will continue to work. This will make it easier to tailor or customize the pattern to work with containers other than Ignition.

* cloud-init changes: move the cloud-init configuration file, user, and password to secrets from edge-gitops-vms values. This was a regrettable oversight in v1.0 and v1.1.

* Common updates: Update common to upstream hybrid-cloud-patterns/common main branch.

* Secrets update: Documented secrets-template is now compliant with the version 2.0 secrets mechanism from hybrid-cloud-patterns/common. Secrets following the older unversioned format will still work.

## Changes for v1.2 (April 27, 2023)

* No "visible" changes so not updating the branch pointer

* Updated ansible code to follow best practices and silent many linting warnings

* Updated edge-gitops-vms chart to add SkipDryRunOnMissingResource annotations to prevent errors occuring due to race conditions with OpenShift Virtualization

* Updated wait-for-metal-nodes machinery to also skip RBAC creation since the only reason for it in e-g-v is for the job, which should only be needed when provisioning a separate metal node as is needed by AWS

* Updated common to refresh vault and external-secrets and pick up default features for gitops-1.8

## Changes for v1.3 (October 27, 2023)

* Introduce Portworx Enterprise as an alternative resilient storage solution for the VMs
* Update common for feature/functionality upgrades
* Update default metal node type from c5n.metal to m5.metal to better accommodate different AWS Zones
* Remove support for 4.10 (since it is out of support)
* Update platform level override using new templated valuefile name feature in common
* Skip multicloud gateway (noobaa) installation in ODF by default

## Changes for v1.4 (July 29, 2024)

* Introduce clean-golden-images job to imperative. This is a workaround for a bug in CNV 4.15/ODF 4.15 where if the default StorageClass is not the same as the default virtualization storage class, CNV cannot properly provision datavolumes.
* Default storageclass for edge-gitops-vms to "ocs-storagecluster-ceph-rbd-virtualization", available since ODF 4.14.
* Use api_version for Route queries when discovering credentials for AAP instance.
* Update common.
* Update deploy_kubevirt_worker.yml Ansible playbook to copy securityGroups and blockDevices config from first machineSet. Tag naming schemes changed from OCP 4.15 to 4.16; this method ensures forward and backward compatibility.
* Remove ODF overrides from OCP 4.12/3 that force storageClass to gp2; all released versions should use gp3-csi now.
* Include overrides for OCP 4.12 and OCP 4.13 to use the older `ocs-storagecluster-ceph-rbd` storageClass.

## Changes for v2.0 (TBD)

* Split HMI Demo Project out to separate [repository](https://github.com/validatedpatterns-demos/rhvp.ansible_edge_hmi)
* Split HMI Config out to separate [repository](https://github.com/validatedpatterns-demos/ansible-edge-gitops-hmi-config-as-code.git)
* Drop the custom execution environment because AAP can resolve these dependencies itself
* Switch to modular common
* Use the Validated Patterns ODF Chart (dropping our custom version)
* Comment out portworx install and test, as the only OCP version that supports is 4.12, which is now past
  the end of its maintenance support lifecycle.
* Refactor installation mechannism to use standard configuration-as-code approach, which will make it easier to drop
  in a new config-as-code repository.
* Move VM definitions outside of edge-gitops-vms chart so that derived patterns do not inherit the HMI kiosks. Kiosk
  VMs now defined by default in overrides.

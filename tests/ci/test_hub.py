import pytest
from ocp_resources.virtual_machine import VirtualMachine
from openshift.dynamic.exceptions import NotFoundError
from validatedpatterns_tests.interop import application, components, subscription


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_subscription_status_hub(openshift_dyn_client):
    expected_subs = {
        "openshift-gitops-operator": ["openshift-gitops-operator"],
        "patterns-operator": ["patterns-operator"],
        "odf-operator": ["openshift-storage"],
        "kubevirt-hyperconverged": ["openshift-cnv"],
        "ansible-automation-platform-operator": ["ansible-automation-platform"],
    }

    subscription.assert_subscription_status(openshift_dyn_client, expected_subs)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_site_reachable_hub(openshift_dyn_client):

    components.assert_site_reachable(openshift_dyn_client)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_pod_status_hub(openshift_dyn_client):
    projects = [
        "patterns-operator",
        "ansible-automation-platform",
        "vp-gitops",
        "edge-gitops-vms",
        "vault",
    ]
    skip_check = []

    components.assert_pod_status(openshift_dyn_client, projects, skip_check)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_argocd_reachable_hub(openshift_dyn_client):
    components.assert_argocd_reachable(openshift_dyn_client)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_argocd_applications_health_hub(openshift_dyn_client):
    projects = ["vp-gitops"]

    application.assert_argocd_applications(openshift_dyn_client, projects)


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_vm_status_hub(openshift_dyn_client):
    expected_vms = {
        "edge-gitops-vms": ["rhel10-kiosk-001", "rhel9-kiosk-001", "rhel8-kiosk-001"],
    }

    missing_vms = []
    unhealthy_vms = []

    for namespace, vm_list in expected_vms.items():
        for vm in vm_list:
            try:
                vms = VirtualMachine.get(
                    dyn_client=openshift_dyn_client, namespace=namespace, name=vm
                )
                vm = next(vms)
            except NotFoundError:
                missing_vms.append(f"{vm} in {namespace} namespace")
                continue

            if not vm.ready:
                unhealthy_vms.append(
                    f"{vm.instance.metadata.name} in {namespace} namespace is {vm.printable_status}"
                )

    errors = []

    if missing_vms:
        errors.append(f"Missing vms: {', '.join(missing_vms)}")

    if unhealthy_vms:
        errors.append(f"Unhealthy vms: {', '.join(unhealthy_vms)}")

    assert not errors, "VM status check failed:\n" + "\n".join(errors)

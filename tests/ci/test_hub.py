import os
import re
import pytest
import subprocess
from pathlib import Path
from ocp_resources.virtual_machine import VirtualMachine
from openshift.dynamic.exceptions import NotFoundError
from playwright.sync_api import Page, expect, sync_playwright
from validatedpatterns_tests.interop import application, components, subscription


from .helpers import (
    kubeadmin_password,
    route_url,
)


def _results_dir():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".results")
    os.makedirs(path, exist_ok=True)
    return path


def _openshift_login(page, url, password):
    page.goto(url)
    page.get_by_label("Username *").fill("kubeadmin")
    page.get_by_label("Password *").fill(password)
    page.get_by_role("button", name="Log in").click()


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


@pytest.mark.parametrize(
    "openshift_dyn_client",
    ["VP_HUBCONFIG"],
    indirect=True,
)
def test_aap_login(openshift_dyn_client):
    console_url = route_url(openshift_dyn_client, "openshift-console", "console")
    secrets_url = console_url + "/k8s/ns/ansible-automation-platform/core~v1~Secret"
    aap_url = route_url(openshift_dyn_client, "ansible-automation-platform", "aap")
    password = kubeadmin_password()
    results_dir = _results_dir()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(ignore_https_errors=True)
        context.grant_permissions(["clipboard-read", "clipboard-write"])
        context.set_default_timeout(120_000)
        page = context.new_page()
        try:
            page.goto(secrets_url)
            _openshift_login(page, secrets_url, password)

            page.wait_for_timeout(5000)

            # Dismiss welcome screen if visible
            welcome = page.get_by_role("button", name="Close")
            if welcome.is_visible(timeout=60):
                welcome.click()

            page.locator('[data-test-id="aap-admin-password"]').click()
            page.locator('[data-test="reveal-values"]').click()
            page.get_by_role("button", name="Copy to clipboard").click()

            clip = page.evaluate("() => navigator.clipboard.readText()")

            page.goto(aap_url)
            page.get_by_role("textbox", name="Username").fill("admin")
            page.get_by_role("textbox", name="Password").click(button="right")
            page.keyboard.press("ControlOrMeta+V")
            page.get_by_role("button", name="Log in").click()

            page.get_by_test_id("platform-overview").click()
            page.get_by_role("button", name="Settings").click()
            page.get_by_test_id("platform-subscription-details").click()

        finally:
            context.close()
            browser.close()

    os.environ["KUBECONFIG"] = os.getenv("VP_HUBCONFIG", "")

    # Verify that the script returns the same password
    result = subprocess.run(
        ["bash", "../../pattern.sh", "../../scripts/ansible_get_credentials.sh"],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert clip in result.stdout
    assert result.stderr == ""

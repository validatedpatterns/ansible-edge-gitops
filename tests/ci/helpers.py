import os

import pytest
import requests
from ocp_resources.gateway_gateway_networking_k8s_io import Gateway
from ocp_resources.route import Route


def route_url(openshift_dyn_client, namespace, name):
    """Return http(s) URL for a named OpenShift Route."""
    routes = [
        route
        for route in Route.get(
            dyn_client=openshift_dyn_client, namespace=namespace, name=name
        )
    ]

    assert (
        len(routes) == 1
    ), f"Expected to find the route '{name}' in the namespace '{namespace}'"

    spec = routes[0].instance.spec
    scheme = "https" if getattr(spec, "tls", None) else "http"
    return f"{scheme}://{spec.host}"


def gateway_url(openshift_dyn_client, namespace, name):
    """Return http(s) URL for a named Gateway API Gateway address."""
    gateways = [
        gateway
        for gateway in Gateway.get(
            dyn_client=openshift_dyn_client, namespace=namespace, name=name
        )
    ]

    assert (
        len(gateways) == 1
    ), f"Expected to find the gateway '{name}' in the namespace '{namespace}'"

    instance = gateways[0].instance
    addresses = getattr(instance.status, "addresses", None) or []
    assert addresses, (
        f"Expected gateway '{namespace}/{name}' to have at least one status address"
    )

    listeners = getattr(instance.spec, "listeners", None) or []
    scheme = "https"
    if listeners and str(listeners[0].protocol).upper() == "HTTP":
        scheme = "http"

    return f"{scheme}://{addresses[0].value}"


def assert_url_reachable(url, timeout=60):
    response = requests.get(url, verify=False, timeout=timeout)
    assert (
        response.status_code == 200
    ), f"Expected a 200 from '{url}' but got {response.status_code}"


def kubeadmin_password():
    """Return kubeadmin password from env or the file next to VP_HUBCONFIG."""
    password = os.getenv("KUBEADMIN_PASSWORD") or os.getenv("VP_KUBEADMIN")
    if password:
        return password.strip()

    kubeconfig = os.getenv("VP_HUBCONFIG")
    if not kubeconfig:
        pytest.fail(
            "Set KUBEADMIN_PASSWORD or VP_HUBCONFIG (with a sibling admin-password file)"
        )

    candidates = []
    if kubeconfig.endswith("-kubeconfig"):
        candidates.append(f"{kubeconfig[: -len('-kubeconfig')]}-admin-password")
    candidates.append(os.path.join(os.path.dirname(kubeconfig), "kubeadmin-password"))

    for path in candidates:
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as handle:
                value = handle.read().strip()
            if value:
                return value

    pytest.fail(
        "kubeadmin password not found; set KUBEADMIN_PASSWORD or place "
        "<cluster>-admin-password next to VP_HUBCONFIG"
    )

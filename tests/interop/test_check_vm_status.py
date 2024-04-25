import logging
import os
import time

import pytest

from . import __loggername__
from .crd import ArgoCD

logger = logging.getLogger(__loggername__)

oc = os.environ["HOME"] + "/oc_client/oc"


@pytest.mark.check_vm_status
def test_check_vm_status(openshift_dyn_client):
    logger.info("Get status for 'edge-gitops-vms' application")
    timeout = time.time() + 60 * 30
    while time.time() < timeout:
        app = ArgoCD.get(
            dyn_client=openshift_dyn_client,
            namespace="ansible-edge-gitops-hub",
            name="edge-gitops-vms",
        )
        app = next(app)
        app_name = app.instance.metadata.name
        app_health = app.instance.status.health.status
        app_sync = app.instance.status.sync.status

        logger.info(f"Status for {app_name} : {app_health} : {app_sync}")

        if app_health == "Healthy" and app_sync == "Synced":
            failed = False
            break
        else:
            logger.info(f"Waiting for {app_name} app to sync")
            time.sleep(30)
            failed = True

    if failed:
        logger.info(app)
        err_msg = "Some or all applications deployed on hub site are unhealthy"
        logger.error(f"FAIL: {err_msg}: {app_name}")
        assert False, err_msg
    else:
        logger.info("PASS: All applications deployed on hub site are healthy.")

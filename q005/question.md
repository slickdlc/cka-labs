# Task: Add a Sidecar Logging Container to WordPress Deployment

**Context:**
Ensure you are operating in the `default` cluster context.

**Target Namespace:**
`default`

**Scenario:**
An existing deployment named `wordpress` is currently running in the `default` namespace. It generates application logs inside its container filesystem at `/var/log/wordpress.log`. To stream these application logs to standard output for cluster-level logging aggregation, you must introduce a dedicated sidecar container to the Pod specification.

**Requirements:**
1. Update the existing `wordpress` deployment in namespace `default` by adding a co-located sidecar container with the following specifications:
   - Container name: `sidecar`
   - Image: `busybox:stable`
   - Command: `/bin/sh -c tail -f /var/log/wordpress.log`

2. Configure a volume mounted at `/var/log` on both containers so that `/var/log/wordpress.log` is accessible to the `sidecar` container.

3. Save the modified configuration and ensure the deployment rolls out successfully. Both containers in the Pod must reach the `Running` and `Ready` state (`2/2`).

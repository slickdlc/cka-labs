# Task: Adjust WordPress Deployment Resource Requests and Limits

**Context:**
Ensure you are operating in the `default` cluster context.

**Target Namespace:**
`default`

**Scenario:**
You are managing a WordPress application running in a Kubernetes cluster. The current Deployment configuration requests excessive node resources, causing scheduling failures and node instability. Your task is to adjust the Pod resource requests and limits to ensure stable operation and balanced resource allocation across the cluster.

**Requirements:**
1. Scale down the `wordpress` Deployment in namespace `default` to `0` replicas.

2. Inspect the worker node allocatable resources and divide the resources evenly across all `3` Pods:
   - Assign fair and equal CPU and memory requests to each Pod.
   - Add sufficient overhead to avoid node instability.

3. Ensure that both the init containers and main containers use exactly the same resource requests and limits.

4. After making the changes, scale the `wordpress` Deployment back to `3` replicas. Ensure that all 3 Pods are successfully scheduled, reach the `Running` state, and become ready.


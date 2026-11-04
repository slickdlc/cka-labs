# Task: Diagnose and Repair Cluster DNS Infrastructure

**Context:**
Ensure you are operating in the `default` context (or the active cluster context).

**Target Namespaces:**
`kube-system` and `analytics`

**Incident Description:**
Multiple workloads deployed across the cluster are reporting critical network failures and service interruptions. Specifically, the pod `data-processor` in namespace `analytics` is failing to resolve the internal database service name `database-svc.analytics.svc.cluster.local`, as well as system cluster services such as `kubernetes.default.svc.cluster.local`.

**Requirements:**
1. Investigate and resolve the root cause of the cluster-wide DNS resolution failure affecting workloads in namespace `kube-system`.
2. Ensure that all Pods belonging to the CoreDNS deployment are in a `Running` and healthy state (`Ready: 1/1`).
3. Verify and ensure that the `kube-dns` Service in namespace `kube-system` has its `Endpoints` correctly mapped to the active CoreDNS pod IPs.
4. Verify that internal cluster DNS resolution is fully functional from the `data-processor` pod in namespace `analytics`, successfully resolving both `database-svc` and `kubernetes.default`.
5. Do not delete or recreate the existing Pods or Service in namespace `analytics`.

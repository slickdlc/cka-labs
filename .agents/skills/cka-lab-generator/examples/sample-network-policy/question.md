# Task: Restrict Backend Traffic Using NetworkPolicy

**Context:**
Ensure you are operating in the `default` context (or the active cluster context).

**Target Namespace:**
`ecommerce`

**Requirements:**
1. In the `ecommerce` namespace, create a `NetworkPolicy` named `allow-frontend-to-backend`.
2. The policy must apply strictly to Pods labeled with `app: backend`.
3. Configure `Ingress` rules to permit incoming traffic **only** from Pods labeled with `app: frontend` within the same `ecommerce` namespace.
4. Incoming traffic must be restricted strictly to TCP port `8080`.
5. Ensure all other incoming traffic to Pods labeled with `app: backend` (including traffic from other labels or outside namespaces) is denied.
6. Do not modify the existing Pods or Services.

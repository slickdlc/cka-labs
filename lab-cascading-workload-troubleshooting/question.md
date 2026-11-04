# Task: Diagnose and Repair Cascading Outage in Production Microservice

**Context:**
Ensure you are operating in the `default` context (or the active cluster context).

**Target Namespace:**
`ecommerce-prod`

**Incident Description:**
An urgent production outage has been reported in namespace `ecommerce-prod`. The critical backend service `order-service` has stopped processing orders, and upstream client requests from `client-frontend` are failing completely. A recent automated pipeline deployment introduced multiple configuration defects across several layers of the application lifecycle and networking stack.

**Requirements:**
1. Investigate and resolve all scheduling constraints so that all 2 replicas of Deployment `order-service` are scheduled and run across cluster nodes.
2. Diagnose and resolve container initialization (`initContainers`) and runtime configuration errors so that all replicas of Deployment `order-service` successfully start, stabilize, and reach full `Ready` status (`1/1`).
3. Ensure the readiness probe on `order-service` correctly validates the health of the application on the container's listening port (`80`) at path `/`.
4. Ensure the Service `order-service` targets the correct backend Pods and routes incoming traffic to the container port `80`. The Service must show active, non-empty endpoints.
5. Reconfigure the existing NetworkPolicy `order-netpol` in namespace `ecommerce-prod` to enforce the following network access rules:
   - Allow incoming (Ingress) TCP traffic on port `80` to `order-service` pods specifically from pods with label `app=client-frontend`.
   - Allow outgoing (Egress) UDP and TCP traffic on port `53` (Cluster DNS) from `order-service` pods.
   - Allow outgoing (Egress) TCP traffic on port `5432` to the database pod `order-db` (`app=order-db`).
6. Functional verification: An HTTP GET request initiated from pod `client-frontend` to `http://order-service.ecommerce-prod.svc.cluster.local:80/` must return an HTTP 200 OK response.
7. Constraints:
   - Do not delete or recreate the pods `client-frontend` or `order-db`.
   - Preserve the Secret `db-credentials` (its existing keys and values must remain unchanged).
   - All 2 replicas of `order-service` must remain in `Running` and `Ready (1/1)` state.

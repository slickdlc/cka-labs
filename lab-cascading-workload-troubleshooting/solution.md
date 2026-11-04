# Official Solution: Cascading Multi-Tier Workload Troubleshooting

## CKA Speed & Diagnostic Strategy

In the CKA exam, troubleshooting cascading failures requires a strict, bottom-up methodology:
$$\text{Scheduling (Pending)} \longrightarrow \text{Init (Pod Initialization)} \longrightarrow \text{Runtime (Crash/Config)} \longrightarrow \text{Readiness (0/1 Ready)} \longrightarrow \text{Endpoints (Service)} \longrightarrow \text{Network Policies}$$

---

### Step 1: Resolve Pod Scheduling Failure (`Pending`)

1. Check the pod status in namespace `ecommerce-prod`:
   ```bash
   kubectl get pods -n ecommerce-prod
   ```
   Both `order-service-...` pods are stuck in `Pending`.

2. Inspect the pod scheduling events:
   ```bash
   kubectl describe pod -l app=order-backend -n ecommerce-prod | grep -A 5 -i "Events:"
   ```
   *Output indicates 0/X nodes available due to node affinity/selector (`disktype: nvme-enterprise`).*

3. Edit the Deployment to remove the `nodeSelector`:
   ```bash
   kubectl edit deploy order-service -n ecommerce-prod
   ```
   *Delete lines under `nodeSelector:` or remove the entire `nodeSelector:` section:*
   ```yaml
   # Remove:
   # nodeSelector:
   #   disktype: nvme-enterprise
   ```

---

### Step 2: Resolve InitContainer Failure (`Init:CrashLoopBackOff`)

1. Observe the new pod status:
   ```bash
   kubectl get pods -n ecommerce-prod
   ```
   Pods are now scheduled but show `Init:Error` or `Init:CrashLoopBackOff`.

2. Inspect the logs of the init container:
   ```bash
   POD_NAME=$(kubectl get pods -n ecommerce-prod -l app=order-backend -o jsonpath='{.items[0].metadata.name}')
   kubectl logs "$POD_NAME" -c init-db-check -n ecommerce-prod
   ```
   *Error reveals connection failure to `invalid-db-endpoint.ecommerce-prod.svc.cluster.local:5432`.*

3. Check available services in the namespace:
   ```bash
   kubectl get svc -n ecommerce-prod
   ```
   *The database service is `order-db-svc`.*

4. Update the init container command in `order-service`:
   ```bash
   kubectl edit deploy order-service -n ecommerce-prod
   ```
   Change the `command` line under `initContainers`:
   ```yaml
   initContainers:
   - name: init-db-check
     image: busybox:1.36
     command: ["sh", "-c", "nc -z -w 2 order-db-svc.ecommerce-prod.svc.cluster.local 5432"]
   ```

---

### Step 3: Resolve Secret Key Reference (`CreateContainerConfigError`)

1. Observe the pod status:
   ```bash
   kubectl get pods -n ecommerce-prod
   ```
   Status changes to `CreateContainerConfigError`.

2. Describe the pod to pinpoint the missing key:
   ```bash
   kubectl describe pod "$POD_NAME" -n ecommerce-prod | grep -i "Error"
   ```
   *Output shows: `Error: couldn't find key db_pass in Secret ecommerce-prod/db-credentials`.*

3. Inspect the actual keys inside `db-credentials`:
   ```bash
   kubectl get secret db-credentials -n ecommerce-prod -o yaml
   ```
   *The secret defines `db_password`, NOT `db_pass`.*

4. Edit Deployment `order-service` to reference `db_password`:
   ```bash
   kubectl edit deploy order-service -n ecommerce-prod
   ```
   Under `env:` -> `DB_PASSWORD`:
   ```yaml
   env:
   - name: DB_PASSWORD
     valueFrom:
       secretKeyRef:
         name: db-credentials
         key: db_password
   ```

---

### Step 4: Fix Readiness Probe Configuration (`0/1 Ready`)

1. Observe the pod status:
   ```bash
   kubectl get pods -n ecommerce-prod
   ```
   Pods are now `Running`, but status is `0/1` (unready).

2. Inspect pod events to identify why the container is not ready:
   ```bash
   kubectl describe pod "$POD_NAME" -n ecommerce-prod | grep -i "Readiness probe failed"
   ```
   *Warning shows: `Readiness probe failed: Get "http://...:8080/health": dial tcp ...:8080: connect: connection refused`.*

3. The application runs Nginx on port `80` with standard root `/`. Edit the deployment:
   ```bash
   kubectl edit deploy order-service -n ecommerce-prod
   ```
   Update `readinessProbe`:
   ```yaml
   readinessProbe:
     httpGet:
       path: /
       port: 80
     initialDelaySeconds: 2
     periodSeconds: 3
   ```

4. Verify that pods transition to `1/1 Ready`:
   ```bash
   kubectl get pods -n ecommerce-prod -l app=order-backend
   ```

---

### Step 5: Fix Service Selector and TargetPort (`Endpoints`)

1. Check endpoints of `order-service`:
   ```bash
   kubectl get endpoints order-service -n ecommerce-prod
   ```
   *Endpoints are `<none>`.*

2. Compare Service selector with Deployment pod labels:
   ```bash
   kubectl get svc order-service -n ecommerce-prod -o jsonpath='{.spec.selector}'
   # Output: {"app":"order-api"}
   kubectl get deploy order-service -n ecommerce-prod -o jsonpath='{.spec.template.metadata.labels}'
   # Output: {"app":"order-backend"}
   ```

3. Patch the Service selector and `targetPort`:
   ```bash
   kubectl patch svc order-service -n ecommerce-prod -p '{"spec":{"selector":{"app":"order-backend"},"ports":[{"port":80,"targetPort":80,"protocol":"TCP"}]}}'
   ```

4. Verify endpoints:
   ```bash
   kubectl get endpoints order-service -n ecommerce-prod
   # Should now list 2 pod IPs with port 80
   ```

---

### Step 6: Fix NetworkPolicy Ingress & Egress Rules

1. Test connection from `client-frontend`:
   ```bash
   kubectl exec client-frontend -n ecommerce-prod -- curl -m 3 http://order-service/
   ```
   *Command hangs and times out.*

2. Inspect `order-netpol`:
   ```bash
   kubectl describe netpol order-netpol -n ecommerce-prod
   ```
   *Notice two issues:*
   - Ingress only permits traffic from `role: web-gateway` (the client pod has `app: client-frontend`).
   - Egress only permits traffic to `app: external-cache` on port 6379, blocking DNS (53) and DB (5432).

3. Apply corrected NetworkPolicy manifest:
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: order-netpol
     namespace: ecommerce-prod
   spec:
     podSelector:
       matchLabels:
         app: order-backend
     policyTypes:
     - Ingress
     - Egress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: client-frontend
       ports:
       - protocol: TCP
         port: 80
     egress:
     - ports:
       - protocol: UDP
         port: 53
       - protocol: TCP
         port: 53
     - to:
       - podSelector:
           matchLabels:
             app: order-db
       ports:
       - protocol: TCP
         port: 5432
   EOF
   ```

---

### Step 7: Final Verification

1. Verify pods and endpoints:
   ```bash
   kubectl get pods,svc,endpoints -n ecommerce-prod
   ```
2. Test end-to-end HTTP request from upstream client:
   ```bash
   kubectl exec client-frontend -n ecommerce-prod -- curl -s http://order-service.ecommerce-prod.svc.cluster.local:80/
   ```
   *Returns HTTP 200 with Nginx welcome HTML.*

# Official Solution Guide: WordPress Pod Resource Requests and Limits

## Exam Strategy & High-Speed Workflow

In the CKA exam, resource management questions test your ability to balance workloads across cluster nodes, configure Pod QoS, and manage init containers alongside application containers.

Estimated completion time: **2-3 minutes**.

---

### Step 1: Scale Down Deployment to 0 Replicas

Immediately scale the `wordpress` deployment to 0 replicas to prevent scheduling churn or eviction loops while modifying resource definitions:

```bash
kubectl scale deployment wordpress -n default --replicas=0
```

---

### Step 2: Inspect Node Allocatable Capacity & Calculate Fair Share

Query the allocatable resources of your worker node(s):

```bash
kubectl describe nodes | grep -A 8 "Allocatable:"
```
Or query via JSONPath:
```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}  CPU: {.status.allocatable.cpu}{"\n"}  Mem: {.status.allocatable.memory}{"\n"}{end}'
```

#### Example Calculation:
Assume a node reports:
- Allocatable CPU: `2000m` (2 cores)
- Allocatable Memory: `2Gi` (~`2048Mi`)

1. **Even Division Across 3 Pods:**
   - Raw CPU share per Pod: `2000m / 3` ≈ `666m`
   - Raw Memory share per Pod: `2048Mi / 3` ≈ `682Mi`

2. **Add Sufficient Overhead (15% - 25% buffer for system daemons & stability):**
   - Safe CPU request per Pod: `250m` (or `200m` to `500m`)
   - Safe Memory request per Pod: `256Mi` (or `300Mi` to `512Mi`)
   - To ensure stability and meet the exam criteria ("both init containers and main containers use exactly the same resource requests and limits"), set requests and limits to identical values:
     - CPU Request & Limit: `250m`
     - Memory Request & Limit: `256Mi`

*(Note: In any standard test cluster, setting `cpu: "250m"` and `memory: "256Mi"` comfortably leaves ample node overhead while satisfying the 3-replica split).*

---

### Step 3: Update Init Container and Main Container Resources

Edit the deployment:

```bash
kubectl edit deployment wordpress -n default
```

Locate `spec.template.spec` and configure identical `resources` blocks for **both** `initContainers` and `containers`:

```yaml
    spec:
      initContainers:
      - name: init-wordpress
        image: busybox:stable
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
      containers:
      - name: wordpress
        image: busybox:stable
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
```

Save and exit (`:wq`).

---

### Step 4: Scale Back Up to 3 Replicas

Scale the deployment back up to 3 replicas:

```bash
kubectl scale deployment wordpress -n default --replicas=3
```

---

### Step 5: Verification

1. **Verify rollout status:**
   ```bash
   kubectl rollout status deployment/wordpress -n default --timeout=60s
   ```

2. **Verify all 3 Pods are Running and Ready:**
   ```bash
   kubectl get pods -n default -l app=wordpress
   ```

3. **Verify matching resources on init and main containers:**
   ```bash
   kubectl get deployment wordpress -n default -o jsonpath='{"Init:\n"}{.spec.template.spec.initContainers[0].resources}{"\nMain:\n"}{.spec.template.spec.containers[0].resources}{"\n"}'
   ```


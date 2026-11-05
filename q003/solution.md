# Step-by-Step Solution: CKA 2025 Q-1 (Reclaim Persistent Storage)

## Problem Overview & Tested Skills
In the CKA exam, workloads often rely on pre-existing or retained storage. This task tests:
1. **PersistentVolume inspection & matching:** Identifying the PV's capacity, access modes, and storage class.
2. **PersistentVolumeClaim (PVC) creation:** Declaring a PVC that matches the PV's characteristics so the Kubernetes volume controller binds them immediately.
3. **Workload manifest patching:** Replacing ephemeral volumes (`emptyDir`) with a `persistentVolumeClaim` volume source.
4. **Rollout stability:** Ensuring the newly mounted workload starts and passes its readiness checks.

---

## High-Speed Solution Workflow (CKA Exam Technique)

### Step 1: Inspect the Existing PersistentVolume
Check the available PersistentVolume in the cluster:
```bash
kubectl get pv
```
*Expected Output:*
```text
NAME         CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
mariadb-pv   250Mi      RWO            Retain           Available                                   1m
```
Take note of:
- **STATUS:** Must be `Available`.
- **CAPACITY:** `250Mi`.
- **ACCESS MODES:** `RWO` (`ReadWriteOnce`).
- **STORAGECLASS:** Note if it has a specific class or empty string.

---

### Step 2: Create the PersistentVolumeClaim (`pvc.yaml`)
Create the PVC named `mariadb` in the `mariadb` namespace matching `ReadWriteOnce` and `250Mi`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
EOF
```

> **CKA Speed Tip:** If working in environments with a default StorageClass or if the PV has no StorageClass, you can explicitly set `storageClassName: ""` (or match the PV's storageClassName) if binding does not happen automatically.

Immediately verify that the PVC is **Bound**:
```bash
kubectl get pvc -n mariadb
```
*Expected Output:*
```text
NAME      STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   AGE
mariadb   Bound    mariadb-pv   250Mi      RWO                           5s
```

---

### Step 3: Edit `~/mariadb-deploy.yaml`
Open the deployment file:
```bash
vi ~/mariadb-deploy.yaml
```

Locate the `volumes` section under `spec.template.spec`:

#### Before:
```yaml
      volumes:
      - name: mariadb-data
        emptyDir: {}
```

#### After:
```yaml
      volumes:
      - name: mariadb-data
        persistentVolumeClaim:
          claimName: mariadb
```

> **Fast command-line alternative (using `sed`):**
> ```bash
> sed -i 's/emptyDir: {}/persistentVolumeClaim:\n          claimName: mariadb/' ~/mariadb-deploy.yaml
> ```

---

### Step 4: Apply the Deployment Manifest
Apply the updated Deployment configuration to the cluster:
```bash
kubectl apply -f ~/mariadb-deploy.yaml
```

---

### Step 5: Verify Deployment and Pod Health
Check rollout status and pod readiness:
```bash
kubectl rollout status deployment mariadb -n mariadb
kubectl get pods -n mariadb
```
*Expected Output:*
```text
NAME                       READY   STATUS    RESTARTS   AGE
mariadb-75bb97b494-x7l9q   1/1     Running   0          25s
```

Verify that the volume is properly mounted:
```bash
kubectl describe pod -n mariadb -l app=mariadb | grep -A 3 "Mounts:"
```

---

## Key Exam Pitfalls to Avoid
1. **Wrong Namespace:** Always ensure the PVC is created in namespace `mariadb`. PVCs are namespace-scoped and cannot be bound by workloads across different namespaces.
2. **AccessMode Mismatch:** The PV is `ReadWriteOnce`. If you specify `ReadWriteMany` in the PVC, it will remain in `Pending` indefinitely.
3. **StorageClass Pitfall:** If your cluster has a default `StorageClass`, Kubernetes will inject that class into any PVC where `storageClassName` is omitted. If the PV was defined with `storageClassName: ""` (or vice-versa), they will not match. Checking `kubectl describe pvc mariadb -n mariadb` will reveal `waiting for a volume to be created, either by dynamic provisioner or manually created`.
4. **Retain Reclaim Policy:** A PV with `persistentVolumeReclaimPolicy: Retain` that was previously bound to another PVC will show status `Released` until its `spec.claimRef` is cleared. In this task, the PV is pre-conditioned in `Available` status.

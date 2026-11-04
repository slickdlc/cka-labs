# Lab Matrix by Official CKA Exam Domain

The Certified Kubernetes Administrator (CKA) exam tests 5 core domains. Below is the breakdown of typical lab scenarios for each domain along with setup and validation considerations.

---

## 1. Cluster Architecture, Installation & Configuration (25%)

### Common Scenarios:
1. **RBAC (Role, ClusterRole, RoleBinding, ClusterRoleBinding, ServiceAccount)**
   - *Setup*: Create namespaces, ServiceAccounts, and test pods.
   - *Validate*: Test with `kubectl auth can-i <verb> <resource> --as=...` for both allowed and denied actions.
2. **Kubeadm Upgrade (Control-plane and Worker nodes)**
   - *Setup*: Cluster running at version $N-1$ (e.g., v1.30.0 targeting v1.31.0).
   - *Validate*: Check `kubeadm version`, `kubelet --version`, and `kubectl get nodes -o jsonpath`.
3. **etcd Backup & Restore**
   - *Setup*: Create test resources in etcd before taking snapshot; simulate disaster by deleting workloads.
   - *Validate*: Run `etcdctl snapshot status` and confirm restored workloads exist post-restore.
4. **Control-plane Static Pods**
   - *Setup*: Modify or corrupt manifests in `/etc/kubernetes/manifests/` (wrong ports, broken certificate paths).
   - *Validate*: Confirm kube-apiserver or kube-scheduler recovers and shows Running in `kube-system`.

---

## 2. Workloads & Scheduling (15%)

### Common Scenarios:
1. **Multi-Container Pods (Sidecar / Adapter Pattern)**
   - *Setup*: Pod or deployment streaming logs to a shared `emptyDir` volume.
   - *Validate*: Verify sidecar reads the volume and processes log output.
2. **Node Affinity & Anti-Affinity**
   - *Setup*: Label nodes (`topology.kubernetes.io/zone=zone1`, `disk=ssd`).
   - *Validate*: Check that Deployment pods land strictly on matching nodes.
3. **Tolerations & Taints**
   - *Setup*: Taint nodes (`dedicated=special:NoSchedule`).
   - *Validate*: Verify target pod is scheduled onto tainted node with matching toleration.
4. **DaemonSets & Worker Node Static Pods**
   - *Setup*: Configure kubelet `staticPodPath: /etc/kubernetes/manifests` on a worker node.
   - *Validate*: Verify static pod with suffix `-<node-name>` is Running.
5. **Node Cordon & Drain with PodDisruptionBudget**
   - *Setup*: Configure PDB (`minAvailable: 2`) and trigger drain.
   - *Validate*: Confirm evictions respect PDB constraints.

---

## 3. Services & Networking (20%)

### Common Scenarios:
1. **NetworkPolicy Ingress & Egress Isolation**
   - *Setup*: Deploy multi-tier app (`frontend`, `backend`, `db`) in one or more namespaces.
   - *Validate*: Execute functional connectivity tests (`wget` / `curl` with timeouts) verifying authorized traffic passes and unauthorized traffic times out.
2. **ClusterIP, NodePort, and Ingress Configuration**
   - *Setup*: Deploy backend pods; configure Ingress Controller.
   - *Validate*: Query Ingress path routes and verify backend responses.
3. **CoreDNS & kube-dns Troubleshooting**
   - *Setup*: Introduce Corefile syntax errors or service selector mismatches in `kube-system`.
   - *Validate*: Run `nslookup` queries from test pods and inspect `endpoints kube-dns`.

---

## 4. Storage (10%)

### Common Scenarios:
1. **PersistentVolume & PersistentVolumeClaim Binding**
   - *Setup*: StorageClass or manual hostPath PV creation with accessModes (`ReadWriteOnce`).
   - *Validate*: Verify PVC status is `Bound` and claims match specified PV capacity.
2. **Volume Mounts and Pod Consumption**
   - *Setup*: Pod writing test data to mounted path.
   - *Validate*: Check mounted directory persistence across pod lifecycle.

---

## 5. Troubleshooting (30%)

### Common Scenarios:
1. **Worker Node Failure (Kubelet / Container Runtime)**
   - *Setup*: Stop or misconfigure kubelet service (`/var/lib/kubelet/config.yaml` or systemd unit).
   - *Validate*: Node returns to `Ready` status in `kubectl get nodes`.
2. **Broken Cluster DNS (CoreDNS Outage)**
   - *Setup*: Misconfigured Corefile ConfigMap or missing kube-dns service endpoints.
   - *Validate*: Verify CoreDNS pods are Ready and internal name resolution succeeds across namespaces.
3. **Crashing Application Pods (CrashLoopBackOff / OOMKilled)**
   - *Setup*: Misconfigured entrypoint, missing environment variables, or insufficient memory limits.
   - *Validate*: Pod stabilizes in `Running` state without restart increments.

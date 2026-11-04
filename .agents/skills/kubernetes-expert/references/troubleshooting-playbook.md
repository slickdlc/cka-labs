# Kubernetes Troubleshooting Playbook

> Systematic troubleshooting guide covering nodes, pods, control plane, networking, storage, and applications. Each section provides symptoms, diagnostic commands, root causes, and solutions.

---

## 1. Node Troubleshooting

### 1.1 Node NotReady

**Symptoms:**
- `kubectl get nodes` shows node status as `NotReady`
- Pods stuck in `Pending` with "no nodes available" events
- Workloads not being scheduled to the affected node

**Diagnostic Commands:**

```bash
# Check node status and conditions
k get nodes
k describe node <node-name>

# Look at the Conditions section for:
#   Ready, MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable

# Check kubelet status on the node
ssh <node>
sudo systemctl status kubelet
sudo journalctl -u kubelet -f --no-pager | tail -50

# Check container runtime
sudo systemctl status containerd
# or
sudo systemctl status cri-o
sudo crictl ps
sudo crictl pods

# Check certificates
sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -text -noout | grep -A2 "Validity"
sudo ls -la /etc/kubernetes/pki/

# Check kubelet config
sudo cat /var/lib/kubelet/config.yaml
sudo cat /etc/kubernetes/kubelet.conf
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| kubelet not running | `sudo systemctl start kubelet && sudo systemctl enable kubelet` |
| kubelet misconfiguration | Check `/var/lib/kubelet/config.yaml` — fix incorrect paths, ports, or auth settings |
| Container runtime down | `sudo systemctl restart containerd` (or docker/cri-o) |
| Expired certificates | Renew with `sudo kubeadm certs renew all` and restart kubelet |
| Incorrect kubeconfig | Check `/etc/kubernetes/kubelet.conf` — verify server URL, certs |
| CNI plugin missing/broken | Check `/etc/cni/net.d/` and `/opt/cni/bin/` — reinstall CNI plugin |
| Firewall blocking | Ensure ports 10250 (kubelet), 6443 (API server) are open |
| Swap enabled | Disable swap: `sudo swapoff -a` and remove from `/etc/fstab` |

### 1.2 Node Resource Pressure

**Symptoms:**
- Node conditions show `DiskPressure`, `MemoryPressure`, or `PIDPressure` as `True`
- Pods being evicted from the node
- Events showing "eviction" messages

**Diagnostic Commands:**

```bash
# Check node conditions
k describe node <node-name> | grep -A5 "Conditions"

# Check resource usage
k top nodes
k top pods --sort-by=memory -A
k top pods --sort-by=cpu -A

# On the node
df -h                           # Disk usage
free -m                         # Memory usage
cat /proc/sys/kernel/pid_max    # PID limit
ps aux | wc -l                  # Process count
du -sh /var/log/*               # Log sizes
sudo crictl images              # Container images consuming disk
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| DiskPressure | Clean up unused images: `sudo crictl rmi --prune`, clean logs, expand disk |
| MemoryPressure | Identify memory-hungry pods with `k top pods`, set resource limits, add more RAM |
| PIDPressure | Identify processes with `ps aux`, check for fork bombs, increase PID limit |
| Image garbage not collected | Check kubelet `imageGCHighThresholdPercent` and `imageGCLowThresholdPercent` |
| Log rotation not configured | Configure logrotate for container logs, set kubelet `containerLogMaxSize` |

### 1.3 kubelet Logs and Configuration

**Key Locations:**

```bash
# kubelet service file
/etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# kubelet configuration
/var/lib/kubelet/config.yaml

# kubelet kubeconfig
/etc/kubernetes/kubelet.conf

# kubelet logs
sudo journalctl -u kubelet -f
sudo journalctl -u kubelet --since "10 minutes ago"

# kubelet static pod manifests path (configured in config.yaml)
# Default: /etc/kubernetes/manifests/

# After editing kubelet config:
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

## 2. Pod Troubleshooting

### 2.1 Pod Lifecycle States

```
Pending → Running → Succeeded
                  → Failed
              → Unknown
```

| State | Meaning |
|---|---|
| **Pending** | Pod accepted but not yet scheduled or images not pulled |
| **Running** | At least one container is running |
| **Succeeded** | All containers terminated successfully (exit 0) |
| **Failed** | All containers terminated, at least one with failure |
| **Unknown** | Pod state cannot be determined (usually node communication issue) |

### 2.2 CrashLoopBackOff

**Symptoms:**
- Pod status shows `CrashLoopBackOff`
- Container restart count keeps increasing
- Exponential back-off delay between restarts (10s, 20s, 40s, ... up to 5min)

**Diagnostic Commands:**

```bash
# Check pod status and restart count
k get pod <pod-name>
k describe pod <pod-name>

# Check current container logs
k logs <pod-name>

# Check PREVIOUS container logs (most important!)
k logs <pod-name> --previous
k logs <pod-name> -c <container-name> --previous

# Check events
k get events --field-selector involvedObject.name=<pod-name> --sort-by=.metadata.creationTimestamp
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Application error / crash | Check logs (`--previous`), fix application code or configuration |
| Missing config/secrets | Verify ConfigMaps and Secrets exist and are correctly mounted |
| Wrong command/args | Check `command` and `args` fields in container spec |
| Insufficient resources | Increase resource limits or fix OOM issues |
| Liveness probe failing | Adjust probe parameters (`initialDelaySeconds`, `timeoutSeconds`, `failureThreshold`) |
| Permission denied | Check security context, file permissions, run as correct user |
| Missing dependencies | Ensure dependent services (databases, APIs) are available |

### 2.3 ImagePullBackOff / ErrImagePull

**Symptoms:**
- Pod stuck in `ImagePullBackOff` or `ErrImagePull`
- Events show "Failed to pull image" messages

**Diagnostic Commands:**

```bash
k describe pod <pod-name>
# Look at Events section for specific error messages

# Common error messages:
# "repository does not exist"
# "unauthorized: authentication required"
# "manifest unknown"
# "net/http: TLS handshake timeout"
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Wrong image name or tag | Verify image:tag exists in the registry |
| Private registry, no credentials | Create docker-registry secret and add `imagePullSecrets` to pod spec |
| Registry unreachable | Check network connectivity from node to registry |
| ImagePullPolicy: Always with no registry access | Use `imagePullPolicy: IfNotPresent` if image is pre-loaded |
| Rate limiting (Docker Hub) | Use authenticated pulls or mirror registry |

```yaml
# Fix: Add imagePullSecrets
spec:
  imagePullSecrets:
  - name: my-registry-secret
  containers:
  - name: app
    image: private-registry.io/my-app:v1
```

### 2.4 OOMKilled

**Symptoms:**
- Container status shows `OOMKilled` (reason)
- Last state: `Terminated` with exit code `137`
- Pod may be in `CrashLoopBackOff` after repeated OOM kills

**Diagnostic Commands:**

```bash
k describe pod <pod-name>
# Look for: Last State: Terminated, Reason: OOMKilled, Exit Code: 137

k top pod <pod-name> --containers

# Check resource limits
k get pod <pod-name> -o jsonpath='{.spec.containers[*].resources}'
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Memory limit too low | Increase `resources.limits.memory` |
| Memory leak in application | Fix application, add proper garbage collection |
| JVM heap not matching container limit | Set `-Xmx` to ~75% of container memory limit |
| No memory limit set (node OOM) | Set appropriate memory limits for all containers |

### 2.5 Evicted Pods

**Symptoms:**
- Pod status shows `Evicted`
- Events mention "evicting pod due to" resource pressure

**Diagnostic Commands:**

```bash
# Find evicted pods
k get pods -A --field-selector=status.phase=Failed | grep Evicted

# Check why
k describe pod <evicted-pod>

# Clean up evicted pods
k get pods -A --field-selector=status.phase=Failed -o json | \
  k delete -f -
# Or per namespace:
k delete pods --field-selector=status.phase=Failed
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Node disk pressure | Free disk space, configure image GC, add storage |
| Node memory pressure | Set proper resource requests/limits, add node capacity |
| Exceeding ephemeral storage limits | Set `ephemeralStorage` limits, clean up temp files in containers |
| Pod without resource requests (BestEffort QoS) | Add resource requests to move to Burstable/Guaranteed QoS |

### 2.6 Pod Stuck in Pending

**Symptoms:**
- Pod stays in `Pending` state indefinitely
- No container is created

**Diagnostic Commands:**

```bash
k describe pod <pod-name>
# Check Events section — the scheduler reports WHY it can't place the pod

k get events --sort-by=.metadata.creationTimestamp | grep <pod-name>
```

**Root Causes and Solutions:**

| Root Cause | Event Message | Solution |
|---|---|---|
| Insufficient CPU/Memory | "Insufficient cpu" / "Insufficient memory" | Reduce requests, add nodes, or delete unused pods |
| No matching node (nodeSelector) | "didn't match Pod's node affinity/selector" | Fix nodeSelector labels or label nodes correctly |
| Taints not tolerated | "had taint ... that the pod didn't tolerate" | Add matching tolerations to pod spec |
| PVC not bound | "persistentvolumeclaim ... not found" or PVC Pending | Fix PVC/PV/StorageClass (see Storage section) |
| ResourceQuota exceeded | "exceeded quota" | Increase quota or reduce resource requests |
| No scheduler running | No events at all | Check kube-scheduler is running |
| Pod affinity/anti-affinity unsat | "didn't match pod (anti)affinity rules" | Adjust affinity rules or add matching pods/nodes |

### 2.7 Debugging Init Containers

**Symptoms:**
- Pod stuck in `Init:0/1`, `Init:Error`, or `Init:CrashLoopBackOff`

**Diagnostic Commands:**

```bash
# Check init container status
k describe pod <pod-name>
# Look at "Init Containers" section

# Logs of init container
k logs <pod-name> -c <init-container-name>

# If init container already completed, check status
k get pod <pod-name> -o jsonpath='{.status.initContainerStatuses}'
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Init container command failing | Check logs, fix command or script |
| Waiting for a service to be ready | Verify dependent service is running and accessible |
| Permission issues | Check security context and RBAC for init container |
| Volume mount issues | Verify volumes are correctly configured |

### 2.8 Multi-Container Pod Debugging

```bash
# List all containers in a pod
k get pod <pod-name> -o jsonpath='{.spec.containers[*].name}'

# Check each container's status
k describe pod <pod-name>

# Logs for specific container
k logs <pod-name> -c <container-name>
k logs <pod-name> -c <container-name> --previous

# Exec into specific container
k exec -it <pod-name> -c <container-name> -- sh

# Check all container statuses
k get pod <pod-name> -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\t"}{.ready}{"\t"}{.restartCount}{"\n"}{end}'
```

---

## 3. Control Plane Troubleshooting

### 3.1 Static Pod Manifests

**Location:** `/etc/kubernetes/manifests/` (on control plane nodes)

```bash
# Static pod manifest files
ls /etc/kubernetes/manifests/
# etcd.yaml
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml

# After modifying a static pod manifest:
# kubelet automatically detects changes and recreates the pod
# If it doesn't restart, move the file out and back in:
cd /etc/kubernetes/manifests/
mv kube-apiserver.yaml /tmp/
# wait for pod to terminate
mv /tmp/kube-apiserver.yaml .
# or restart kubelet
sudo systemctl restart kubelet
```

### 3.2 API Server Issues

**Symptoms:**
- `kubectl` commands fail with "connection refused" or timeout
- Other control plane components show connection errors
- `The connection to the server was refused`

**Diagnostic Commands:**

```bash
# Check API server pod
sudo crictl ps | grep kube-apiserver
sudo crictl logs <apiserver-container-id>

# Check static pod manifest
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml

# Check if API server is listening
sudo ss -tlnp | grep 6443
curl -k https://localhost:6443/healthz

# Check API server logs
sudo journalctl -u kubelet | grep apiserver
kubectl -n kube-system logs kube-apiserver-<node-name>
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Manifest syntax error | Fix YAML in `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| Wrong etcd endpoint | Verify `--etcd-servers` flag points to correct etcd address |
| Certificate expired | `kubeadm certs check-expiration`, then `kubeadm certs renew all` |
| Wrong certificate paths | Verify `--tls-cert-file`, `--tls-private-key-file`, etc. |
| Port conflict | Check nothing else is using port 6443 |
| Insufficient resources | Check node has enough CPU/memory for API server |
| Wrong `--service-cluster-ip-range` | Must match cluster configuration |

### 3.3 etcd Issues

**Symptoms:**
- API server unable to store/retrieve data
- Error messages mentioning etcd timeouts or connection failures
- Cluster state not persisting

**Diagnostic Commands:**

```bash
# Check etcd pod
sudo crictl ps | grep etcd
sudo crictl logs <etcd-container-id>

# Check etcd health using etcdctl
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Check etcd member list
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Check etcd data directory
ls -la /var/lib/etcd/

# etcd backup
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db

# etcd restore
sudo ETCDCTL_API=3 etcdctl \
  snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored
# Then update etcd manifest to point to new data dir
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| etcd not running | Check manifest, fix configuration, restart kubelet |
| Data directory permissions | `sudo chown -R etcd:etcd /var/lib/etcd` (or root depending on setup) |
| Disk full | Free space in etcd data directory |
| Certificate mismatch | Ensure etcd certs match what API server expects |
| Wrong data directory path | Fix `--data-dir` in etcd manifest |
| Corrupted data | Restore from backup |

### 3.4 Controller Manager Issues

**Symptoms:**
- Deployments not creating ReplicaSets
- ReplicaSets not creating Pods
- Services not getting Endpoints
- Nodes not getting garbage collected

**Diagnostic Commands:**

```bash
# Check controller manager
sudo crictl ps | grep controller-manager
sudo crictl logs <controller-manager-container-id>
k -n kube-system logs kube-controller-manager-<node-name>

# Check manifest
sudo cat /etc/kubernetes/manifests/kube-controller-manager.yaml
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Manifest syntax error | Fix YAML syntax |
| Wrong CA or cert paths | Verify certificate file paths exist and are correct |
| Can't reach API server | Check API server is healthy, verify `--kubeconfig` or `--master` flag |
| Leader election issues (HA) | Check `--leader-elect` flag and lease objects |

### 3.5 Scheduler Issues

**Symptoms:**
- Pods stuck in `Pending` with no scheduling events
- No "Scheduled" events appearing

**Diagnostic Commands:**

```bash
# Check scheduler
sudo crictl ps | grep scheduler
sudo crictl logs <scheduler-container-id>
k -n kube-system logs kube-scheduler-<node-name>

# Check manifest
sudo cat /etc/kubernetes/manifests/kube-scheduler.yaml

# Verify scheduler is functional
k get events -A | grep Scheduled
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Scheduler not running | Fix manifest, restart kubelet |
| Wrong port/bind address | Check `--secure-port` and `--bind-address` |
| Can't reach API server | Verify API server connectivity |
| Custom scheduler name mismatch | Pod's `schedulerName` must match a running scheduler |

### 3.6 Certificate Problems

```bash
# Check certificate expiration (kubeadm clusters)
sudo kubeadm certs check-expiration

# Renew all certificates
sudo kubeadm certs renew all
sudo systemctl restart kubelet

# Check specific certificate
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A2 "Validity"

# Certificate file inventory
ls -la /etc/kubernetes/pki/
# apiserver.crt / apiserver.key              — API server serving cert
# apiserver-kubelet-client.crt/key           — API server → kubelet
# apiserver-etcd-client.crt/key              — API server → etcd
# ca.crt / ca.key                            — Cluster CA
# front-proxy-ca.crt / front-proxy-client.*  — Aggregation layer
# sa.key / sa.pub                            — Service account signing

ls -la /etc/kubernetes/pki/etcd/
# ca.crt / ca.key                            — etcd CA
# server.crt / server.key                    — etcd server cert
# peer.crt / peer.key                        — etcd peer communication
# healthcheck-client.crt/key                 — etcd health checks
```

### 3.7 Component Log Locations

```bash
# Control plane components (static pods)
k -n kube-system logs kube-apiserver-<node>
k -n kube-system logs kube-controller-manager-<node>
k -n kube-system logs kube-scheduler-<node>
k -n kube-system logs etcd-<node>

# Or via container runtime
sudo crictl ps
sudo crictl logs <container-id>

# kubelet (systemd service — NOT a pod)
sudo journalctl -u kubelet

# kube-proxy (DaemonSet)
k -n kube-system logs <kube-proxy-pod>

# CoreDNS
k -n kube-system logs <coredns-pod>

# If journald logs are too verbose:
sudo journalctl -u kubelet --since "5 minutes ago" --no-pager
sudo journalctl -u kubelet -p err    # Only errors
```

---

## 4. Networking Troubleshooting

### 4.1 Service Endpoints Verification

**Symptoms:**
- Service exists but traffic doesn't reach pods
- `curl` to ClusterIP times out or connection refused

**Diagnostic Commands:**

```bash
# Check service has endpoints
k get endpoints <service-name>
k describe svc <service-name>

# Compare service selector with pod labels
k get svc <service-name> -o jsonpath='{.spec.selector}'
k get pods --show-labels

# Verify pods are Ready
k get pods -l <selector-labels>
k get pods -l app=nginx -o wide

# Test from within the cluster
k run tmp --image=busybox --rm -it --restart=Never -- wget -O- http://<service-name>:<port>
k run tmp --image=curlimages/curl --rm -it --restart=Never -- curl http://<service-name>:<port>
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| No endpoints (selector mismatch) | Fix service selector to match pod labels |
| Pods not Ready | Fix readiness probes, check pod health |
| Wrong port/targetPort | Verify `port` and `targetPort` in service spec match container port |
| Pods in wrong namespace | Service and pods must be in the same namespace (for non-FQDN access) |

### 4.2 DNS Resolution

**Symptoms:**
- Pods can't resolve service names
- `nslookup` or `dig` fails inside pods
- Application connection failures by hostname

**Diagnostic Commands:**

```bash
# Test DNS from a debug pod
k run dnstest --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes
k run dnstest --image=busybox:1.28 --rm -it --restart=Never -- nslookup <service-name>
k run dnstest --image=busybox:1.28 --rm -it --restart=Never -- nslookup <service-name>.<namespace>.svc.cluster.local

# Check CoreDNS pods
k get pods -n kube-system -l k8s-app=kube-dns
k logs -n kube-system -l k8s-app=kube-dns

# Check CoreDNS ConfigMap
k get cm coredns -n kube-system -o yaml

# Check pod's DNS config
k exec <pod-name> -- cat /etc/resolv.conf

# Check CoreDNS service
k get svc kube-dns -n kube-system
```

**DNS Name Formats:**

| Resource | DNS Name |
|---|---|
| Service | `<svc>.<namespace>.svc.cluster.local` |
| Pod (dashed IP) | `<pod-ip-dashed>.<namespace>.pod.cluster.local` |
| Headless Service Pod | `<pod-name>.<svc>.<namespace>.svc.cluster.local` |

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| CoreDNS pods not running | Check CoreDNS deployment, restart pods |
| CoreDNS CrashLoopBackOff | Check logs, often a loop detection issue — edit Corefile |
| Wrong resolv.conf in pod | Check pod's `dnsPolicy` — should usually be `ClusterFirst` |
| Network plugin issues | Verify CNI plugin is working, check pod-to-pod connectivity |
| CoreDNS ConfigMap error | Fix syntax in Corefile ConfigMap |

### 4.3 NetworkPolicy Debugging

**Symptoms:**
- Pods can't communicate with each other after NetworkPolicy is applied
- Traffic allowed when it shouldn't be (missing policies)
- Partial connectivity failures

**Diagnostic Commands:**

```bash
# List network policies
k get networkpolicy -A
k describe networkpolicy <policy-name>

# Check if ANY policy selects a pod (if yes, default deny applies)
k get networkpolicy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podSelector}{"\n"}{end}'

# Test connectivity between pods
k exec -it <source-pod> -- wget -O- --timeout=2 http://<dest-pod-ip>:<port>
k exec -it <source-pod> -- nc -zv <dest-pod-ip> <port>

# Check pod labels match policy selectors
k get pods --show-labels
```

**Key NetworkPolicy Concepts:**

```yaml
# Default deny all ingress in a namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}       # Selects ALL pods in namespace
  policyTypes:
  - Ingress
  # No ingress rules = deny all ingress

# Default deny all egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress
  # No egress rules = deny all egress (including DNS!)
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Default deny blocking traffic | Add explicit allow rules for needed traffic |
| Egress policy blocking DNS | Add egress rule allowing port 53 (TCP/UDP) to kube-dns |
| Wrong podSelector | Fix label selectors in the NetworkPolicy |
| Wrong namespaceSelector | Use correct namespace labels |
| CNI doesn't support NetworkPolicy | Use a CNI that supports it (Calico, Cilium, Weave) — Flannel does NOT |
| Policy in wrong namespace | NetworkPolicy must be in the same namespace as the target pods |

### 4.4 kube-proxy Issues

**Symptoms:**
- Services not load-balancing to pods
- ClusterIP/NodePort not reachable
- Endpoints exist but service doesn't work

**Diagnostic Commands:**

```bash
# Check kube-proxy pods
k get pods -n kube-system -l k8s-app=kube-proxy
k logs -n kube-system <kube-proxy-pod>

# Check kube-proxy mode
k -n kube-system get cm kube-proxy -o yaml | grep mode
# "" or "iptables" = iptables mode
# "ipvs" = IPVS mode

# Check iptables rules (on node)
sudo iptables -t nat -L -n | grep <service-clusterip>
sudo iptables -t nat -L KUBE-SERVICES -n

# Check IPVS rules (if using IPVS mode)
sudo ipvsadm -L -n

# Check kube-proxy ConfigMap
k get cm kube-proxy -n kube-system -o yaml
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| kube-proxy not running | Check DaemonSet, restart pods |
| ConfigMap misconfiguration | Fix kube-proxy ConfigMap and restart pods |
| Wrong mode configured | Verify iptables/IPVS mode matches cluster setup |
| iptables rules not being created | Check kube-proxy logs for errors, restart |

### 4.5 CNI Plugin Problems

**Symptoms:**
- Pods stuck in `ContainerCreating` with network errors
- Pod-to-pod communication fails
- Node shows `NetworkUnavailable` condition

**Diagnostic Commands:**

```bash
# Check CNI configuration
ls /etc/cni/net.d/
cat /etc/cni/net.d/*.conflist

# Check CNI binaries
ls /opt/cni/bin/

# Check CNI plugin pods (e.g., Calico, Flannel, Weave)
k get pods -n kube-system | grep -E "calico|flannel|weave|cilium"
k logs -n kube-system <cni-pod>

# Check node network condition
k describe node <node> | grep -i "NetworkUnavailable"
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| CNI plugin not installed | Install CNI plugin (e.g., `k apply -f calico.yaml`) |
| CNI config missing/wrong | Check `/etc/cni/net.d/` — remove conflicting configs |
| CNI binary missing | Ensure required binaries exist in `/opt/cni/bin/` |
| Pod CIDR conflict | Verify CNI pod CIDR matches `--pod-network-cidr` from `kubeadm init` |
| CNI pods crashing | Check CNI pod logs, often RBAC or config issues |

---

## 5. Storage Troubleshooting

### 5.1 PVC Stuck in Pending

**Symptoms:**
- PVC status shows `Pending`
- Pod using the PVC stuck in `Pending` (waiting for volume)
- Events show "waiting for a volume to be created"

**Diagnostic Commands:**

```bash
# Check PVC status
k get pvc
k describe pvc <pvc-name>

# Check available PVs
k get pv

# Check StorageClass
k get storageclass
k describe storageclass <sc-name>

# Check events
k get events --sort-by=.metadata.creationTimestamp | grep -i "pvc\|volume\|provision"
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| No matching PV (static provisioning) | Create a PV that matches PVC's capacity, accessModes, and storageClassName |
| StorageClass doesn't exist | Create the referenced StorageClass or use an existing one |
| No default StorageClass | Add `storageclass.kubernetes.io/is-default-class: "true"` annotation |
| Provisioner not running | Check CSI driver or cloud provider provisioner pods |
| AccessMode mismatch | PV and PVC accessModes must be compatible |
| Capacity mismatch | PV capacity must be ≥ PVC requested capacity |
| StorageClass name mismatch | PVC `storageClassName` must exactly match PV's `storageClassName` |
| Wrong `volumeMode` | PV and PVC must both be `Filesystem` or both be `Block` |

### 5.2 PV Binding Issues

**Common PV States:**

| Status | Meaning |
|---|---|
| Available | PV is free and not yet bound |
| Bound | PV is bound to a PVC |
| Released | PVC was deleted, PV retains data but not yet available |
| Failed | PV automatic reclamation failed |

**Diagnostic Commands:**

```bash
# Check PV details
k get pv
k describe pv <pv-name>

# Check what PVC it's bound to (or should bind to)
k get pv <pv-name> -o jsonpath='{.spec.claimRef}'

# PV stuck in Released — make it Available again
# Option 1: Delete the claimRef (data may be at risk)
k patch pv <pv-name> --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'

# Option 2: Delete and recreate PV
k delete pv <pv-name>
# Then recreate with same spec
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| PV in Released state | Remove `claimRef` or recreate PV |
| Reclaim policy is Retain | Manual intervention needed after PVC deletion |
| Node affinity constraint | PV's nodeAffinity must match the node where pod is scheduled |
| Label selector mismatch | PV labels must match PVC's `selector.matchLabels` |

### 5.3 StorageClass Problems

```bash
# List StorageClasses
k get storageclass
k describe storageclass <sc-name>

# Check default StorageClass
k get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'

# Common StorageClass fields to verify
# - provisioner: must match an installed CSI driver or in-tree provisioner
# - reclaimPolicy: Delete (default) or Retain
# - volumeBindingMode: Immediate or WaitForFirstConsumer
# - allowVolumeExpansion: true/false
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Provisioner not installed | Install the required CSI driver |
| WaitForFirstConsumer with no pod | PVC stays Pending until a pod uses it — this is expected behavior |
| Multiple default StorageClasses | Remove default annotation from extras — only one should be default |
| Volume expansion not allowed | Set `allowVolumeExpansion: true` in StorageClass |

---

## 6. Application Troubleshooting

### 6.1 Readiness/Liveness Probe Failures

**Symptoms:**
- **Readiness probe failure:** Pod is `Running` but not `Ready` (0/1), removed from Service endpoints
- **Liveness probe failure:** Container gets restarted, may enter `CrashLoopBackOff`
- **Startup probe failure:** Container killed before it can start, liveness/readiness probes don't run

**Diagnostic Commands:**

```bash
# Check probe configuration and status
k describe pod <pod-name>
# Look for:
#   "Readiness probe failed:" / "Liveness probe failed:"
#   in Events section

# Check if pod is Ready
k get pod <pod-name> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Check container restarts (indicates liveness failures)
k get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].restartCount}'

# Test the probe endpoint manually
k exec -it <pod-name> -- wget -O- http://localhost:<port><path>
k exec -it <pod-name> -- curl http://localhost:<port><path>

# For TCP probe — check port is listening
k exec -it <pod-name> -- nc -zv localhost <port>

# For exec probe — run the command
k exec -it <pod-name> -- <probe-command>
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Wrong probe path/port | Verify `httpGet.path`, `httpGet.port` match application |
| `initialDelaySeconds` too short | Increase to allow app startup time |
| `timeoutSeconds` too low | Increase if app responds slowly under load |
| `periodSeconds` too aggressive | Increase interval between checks |
| `failureThreshold` too low | Increase to allow transient failures |
| Application not listening on expected port | Fix application bind address/port |
| TLS required but probe uses HTTP | Use `httpGet.scheme: HTTPS` or switch to TCP probe |
| Wrong exec command | Fix the command in the probe spec |

**Probe Configuration Example:**

```yaml
containers:
- name: app
  livenessProbe:
    httpGet:
      path: /healthz
      port: 8080
    initialDelaySeconds: 15     # Wait before first check
    periodSeconds: 10           # Check every 10s
    timeoutSeconds: 5           # Timeout per check
    failureThreshold: 3         # Fail after 3 consecutive failures
    successThreshold: 1         # Succeed after 1 success
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
    failureThreshold: 3
  startupProbe:
    httpGet:
      path: /healthz
      port: 8080
    failureThreshold: 30        # 30 * 10 = 300s max startup time
    periodSeconds: 10
```

### 6.2 Resource Quota Exceeded

**Symptoms:**
- Pod creation fails with "exceeded quota" error
- Deployment can't scale up
- Events mention `forbidden: exceeded quota`

**Diagnostic Commands:**

```bash
# Check quota in namespace
k get resourcequota -n <namespace>
k describe resourcequota <quota-name> -n <namespace>

# Check LimitRange
k get limitrange -n <namespace>
k describe limitrange <limitrange-name> -n <namespace>

# Check current resource usage vs quota
k describe resourcequota <quota-name>
# Shows: Used / Hard for each resource
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| Pod count exceeded | Delete unused pods or increase `pods` quota |
| CPU/Memory requests exceeded | Reduce resource requests or increase quota |
| No resource requests set (with quota) | ResourceQuota requires pods to specify requests — add them |
| LimitRange defaults too high | Adjust LimitRange default values |
| Too many services/configmaps/etc | Clean up unused resources or increase quota |

### 6.3 ConfigMap/Secret Mount Issues

**Symptoms:**
- Pod stuck in `ContainerCreating`
- Events show "configmap not found" or "secret not found"
- Application can't read expected config files
- Mounted files have wrong content or permissions

**Diagnostic Commands:**

```bash
# Check if ConfigMap/Secret exists
k get configmap <cm-name>
k get secret <secret-name>

# Check pod volume mounts
k describe pod <pod-name>
# Look at Volumes and Container Mounts sections

# Verify mounted data
k exec -it <pod-name> -- ls -la /path/to/mount
k exec -it <pod-name> -- cat /path/to/mount/key

# Check if env vars from ConfigMap/Secret are set
k exec -it <pod-name> -- env | grep <expected-var>
```

**Root Causes and Solutions:**

| Root Cause | Solution |
|---|---|
| ConfigMap/Secret doesn't exist | Create the missing ConfigMap or Secret |
| Name mismatch | Verify `configMapRef.name` or `secretRef.name` matches exactly |
| Wrong namespace | ConfigMap/Secret must be in same namespace as pod |
| Key doesn't exist in ConfigMap | Verify the key exists: `k get cm <name> -o yaml` |
| Optional not set | Add `optional: true` if the ConfigMap/Secret may not exist |
| `subPath` prevents auto-updates | ConfigMaps/Secrets mounted with `subPath` won't auto-update — remount without subPath or restart pod |
| Wrong `defaultMode` | Fix `defaultMode` (octal permissions, e.g., `0644`) in volume spec |
| `immutable: true` preventing changes | Delete and recreate the ConfigMap/Secret to update it |

---

## Troubleshooting Decision Tree

```
Pod not working?
├── Status: Pending
│   ├── Events mention scheduling? → Node/resource/affinity issue (Section 2.6)
│   ├── Events mention PVC? → Storage issue (Section 5)
│   └── No events? → Scheduler issue (Section 3.5)
├── Status: ContainerCreating
│   ├── Image pull error? → Image/registry issue (Section 2.3)
│   ├── Mount error? → ConfigMap/Secret/Volume issue (Section 6.3, 5)
│   └── Network error? → CNI issue (Section 4.5)
├── Status: Running but not Ready
│   └── Readiness probe failing? → Probe configuration (Section 6.1)
├── Status: CrashLoopBackOff
│   ├── OOMKilled? → Memory issue (Section 2.4)
│   ├── Exit code 1? → Application error — check logs (Section 2.2)
│   └── Liveness probe? → Probe misconfiguration (Section 6.1)
├── Status: Error / Failed
│   └── Check logs and events (Section 2.2)
└── Status: Init:Error / Init:CrashLoopBackOff
    └── Init container issue (Section 2.7)

Service not working?
├── No endpoints? → Selector/label mismatch (Section 4.1)
├── DNS not resolving? → CoreDNS issue (Section 4.2)
├── Endpoints exist but no connectivity? → kube-proxy or NetworkPolicy (Section 4.3, 4.4)
└── Timeout? → Network/CNI issue (Section 4.5)

Node not working?
├── NotReady? → kubelet/runtime/certs (Section 1.1)
├── Resource pressure? → Disk/Memory/PID (Section 1.2)
└── Unschedulable? → Cordon/Taint (remove with uncordon/untaint)

Control plane issue?
├── kubectl not responding? → API server (Section 3.2)
├── Resources not being created? → Controller manager (Section 3.4)
├── Pods not scheduling? → Scheduler (Section 3.5)
└── Data inconsistency? → etcd (Section 3.3)
```

---

## Quick Diagnostic Commands Cheat Sheet

```bash
# Overall cluster health
k get nodes
k get pods -A | grep -v Running
k get events -A --sort-by=.metadata.creationTimestamp | tail -20
k top nodes
k top pods -A --sort-by=cpu | head -10

# Control plane health
k get pods -n kube-system
k get cs                    # Component status (deprecated but still works)

# Pod investigation (in order)
k get pod <pod> -o wide
k describe pod <pod>        # Check Events section FIRST
k logs <pod>
k logs <pod> --previous
k exec -it <pod> -- sh

# Service investigation
k get svc <svc>
k get endpoints <svc>
k describe svc <svc>

# Node investigation
k describe node <node>
ssh <node>
sudo systemctl status kubelet
sudo journalctl -u kubelet | tail -50
```

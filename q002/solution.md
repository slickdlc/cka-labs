# Step-by-Step Solution: Troubleshooting CoreDNS

## Diagnostic Summary
This exercise reproduces a multi-layer failure commonly featured in high-difficulty simulators (like **Killer.sh**) and advanced CKA exams:
1. **Pod / Application Layer Failure:** The ConfigMap `coredns` contains an invalid directive (`forwarders` instead of `forward`), causing the pods to crash with `CrashLoopBackOff` when parsing the `Corefile`.
2. **Network / Service Layer Failure (The Hidden Trap):** Even after fixing the ConfigMap and getting pods to `Running`, DNS queries continue to fail because the Service `kube-dns` has a broken selector (`k8s-app: coredns-invalid-selector`), leaving `Endpoints` at `<none>`.

---

## Fast Troubleshooting Workflow (CKA Exam Technique)

### Step 1: Reproduce and Isolate the Failure
Confirm the DNS failure by running `nslookup` from the problematic workload:
```bash
kubectl exec -n analytics data-processor -- nslookup database-svc
# Expected error: server can't find database-svc / connection timed out / no servers could be reached
```

### Step 2: Inspect CoreDNS Infrastructure Status
Check the status of CoreDNS pods in namespace `kube-system`:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```
Notice that pods are in `CrashLoopBackOff` or `Error`.

Check logs from one of the crashing pods:
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```
**Key error identified:**
```text
plugin/forwarders: unknown directive 'forwarders'
```

### Step 3: Fix the ConfigMap `coredns`
Edit the ConfigMap:
```bash
kubectl edit configmap coredns -n kube-system
```
Locate the typo inside the `Corefile` data block:
```text
# BEFORE:
forwarders . /etc/resolv.conf

# FIX TO:
forward . /etc/resolv.conf
```
Save and exit (`:wq`).

### Step 4: Restart CoreDNS Pods
Force a rollout restart so the pods adopt the corrected ConfigMap:
```bash
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system
```
Verify that all pods now show `1/1 Running`:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

---

### Step 5: Watch Out for the Hidden Trap! Check Endpoints
Many candidates stop here thinking the issue is resolved. Check the Endpoints of `kube-dns`:
```bash
kubectl get endpoints kube-dns -n kube-system
```
**Critical symptom:**
```text
NAME       ENDPOINTS   AGE
kube-dns   <none>      ...
```
Endpoints are empty (`<none>`)! Even though the pods are running, incoming DNS traffic sent to the cluster DNS IP (`10.96.0.10`) has no backend targets.

### Step 6: Fix the Service Selector for `kube-dns`
Inspect pod labels and the service selector:
```bash
# View pod labels:
kubectl get pods -n kube-system -l k8s-app=kube-dns --show-labels

# View service selector:
kubectl get svc kube-dns -n kube-system -o yaml | grep -A 3 selector
```
Notice the selector mismatch (`coredns-invalid-selector` vs `kube-dns`).

Patch the service selector to match the actual pod labels:
```bash
kubectl patch service kube-dns -n kube-system -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'
```
*(Alternative: `kubectl edit svc kube-dns -n kube-system` and set `spec.selector.k8s-app: kube-dns`)*.

### Step 7: Confirm Endpoints are Populated
```bash
kubectl get endpoints kube-dns -n kube-system
```
You should now see the active pod IPs:
```text
NAME       ENDPOINTS                     AGE
kube-dns   10.244.0.5:53,10.244.0.6:53   ...
```

---

### Step 8: Final Verification
Test internal DNS resolution from the `data-processor` pod:
```bash
kubectl exec -n analytics data-processor -- nslookup database-svc
kubectl exec -n analytics data-processor -- nslookup kubernetes.default
```
Both queries should now immediately return valid service IP addresses.

Run the automated validation script:
```bash
bash validate.sh
```
Expected output: `SUCCESS!` with exit code `0`.

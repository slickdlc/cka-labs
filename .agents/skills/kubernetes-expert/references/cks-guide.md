# CKS — Certified Kubernetes Security Specialist (Exam Guide & Mastery)

The Certified Kubernetes Security Specialist (CKS) is the most challenging practical exam in the CNCF certification program. It tests your ability to secure container-based applications and Kubernetes platforms during build, deployment, and runtime.

- **Prerequisite**: Active or previously passed **CKA** certification
- **Exam Duration**: 120 minutes (2 hours)
- **Format**: ~15–18 complex hands-on performance tasks
- **Passing Score**: 67%
- **Allowed Resources**: Official docs (`kubernetes.io/docs`, `falco.org/docs`, `aquasecurity.github.io/trivy`, AppArmor docs, Sysdig docs).

---

## 📊 Exam Domain Weights

| Domain | Weight | Key Competencies |
| :--- | :---: | :--- |
| **1. Minimize Microservice Vulnerabilities** | **20%** | Pod Security Standards, Secrets encryption, sandboxing (gVisor/Kata), mTLS |
| **2. Supply Chain Security** | **20%** | Minimal base images, Trivy scanning, image signing (Cosign), static manifest analysis |
| **3. Monitoring, Logging & Runtime Security** | **20%** | Falco behavioral detection, API audit logging, incident response |
| **4. Cluster Hardening** | **15%** | Restrict API access, RBAC least privilege, ServiceAccounts, secure upgrades |
| **5. System Hardening** | **15%** | Host OS footprint, AppArmor, Seccomp, kernel security, metadata protection |
| **6. Cluster Setup** | **10%** | CIS Benchmarks (`kube-bench`), NetworkPolicies, Ingress TLS, binary checksums |

---

## 🛡️ Domain 1: Minimize Microservice Vulnerabilities (20%)

### 1.1 Pod Security Standards (PSS) & Admission (PSA)
Pod Security Standards replace deprecated PodSecurityPolicies with three levels:
- **Privileged**: Unrestricted
- **Baseline**: Minimally restrictive, prevents known privilege escalations
- **Restricted**: Hardened against current pod privilege escalation patterns

Namespace-level enforcement using built-in admission labels:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secured-apps
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
```

### 1.2 Kubernetes Secrets Encryption at Rest
By default, secrets in `etcd` are stored unencrypted in base64. To encrypt them:

1. Create encryption configuration file: `/etc/kubernetes/etcd/ec.yaml`
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: c3VwZXJTZWNyZXRLZXkxMjM0NTY3ODkwMTI= # 32 bytes base64 encoded
      - identity: {} # Allows reading existing unencrypted secrets
```
Generate key: `head -c 32 /dev/urandom | base64`

2. Add flag to `/etc/kubernetes/manifests/kube-apiserver.yaml`:
```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --encryption-provider-config=/etc/kubernetes/etcd/ec.yaml
    volumeMounts:
    - name: enc-vol
      mountPath: /etc/kubernetes/etcd/ec.yaml
      readOnly: true
  volumes:
  - name: enc-vol
    hostPath:
      path: /etc/kubernetes/etcd/ec.yaml
      type: File
```

3. Re-encrypt all existing secrets:
```bash
kubectl get secrets -A -o json | kubectl replace -f -
```

### 1.3 Container Sandboxing with RuntimeClass (gVisor / Kata)
Run un-trusted workloads inside a user-space kernel sandbox (`runsc`):

```yaml
# 1. Register RuntimeClass
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
---
# 2. Assign workload to runtime class
apiVersion: v1
kind: Pod
metadata:
  name: isolated-workload
spec:
  runtimeClassName: gvisor
  containers:
  - name: untrusted-app
    image: nginx
```

---

## 🔍 Domain 2: Supply Chain Security (20%)

### 2.1 Image Vulnerability Scanning with Trivy
```bash
# Scan container image for HIGH and CRITICAL vulnerabilities
trivy image --severity HIGH,CRITICAL nginx:1.24

# Exit with non-zero code if critical CVEs found (useful for CI/CD gates)
trivy image --exit-code 1 --severity CRITICAL alpine:3.18

# Scan local file or Kubernetes manifest
trivy config ./manifest.yaml
```

### 2.2 Enforcing Image Integrity & Minimal Images
- Never use `:latest` in production manifests.
- Prefer Distroless (`gcr.io/distroless/static-debian12`) or Alpine to minimize attack vectors.
- Remove package managers (`curl`, `apk`, `apt`, `yum`) from production images.

---

## 👁️ Domain 3: Monitoring, Logging & Runtime Security (20%)

### 3.1 Falco Runtime Behavioral Threat Detection
Falco uses eBPF/kernel drivers to detect anomalous activity:
- Rules location: `/etc/falco/falco_rules.yaml` & `/etc/falco/falco_rules.local.yaml`
- Service status: `systemctl status falco`
- Inspect alerts: `journalctl -u falco -n 50 -f` or `/var/log/syslog`

Writing a custom Falco rule in `/etc/falco/falco_rules.local.yaml`:
```yaml
- rule: Shell Spawned in Container
  desc: Detect any interactive shell spawned inside a running pod
  condition: >
    spawned_process and container and
    proc.name in (bash, sh, zsh, ksh)
  output: >
    Warning: Shell opened in container (user=%user.name container=%container.name pod=%k8s.pod.name image=%container.image.repository)
  priority: WARNING
  tags: [container, shell]
```
After editing, hot-reload or restart Falco: `sudo systemctl restart falco`

### 3.2 Kubernetes API Audit Logging
Configure the API Server to log administrative and user interactions.

1. Create policy file `/etc/kubernetes/audit/policy.yaml`:
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Don't log read-only health checks
  - level: None
    nonResourceURLs:
      - "/healthz*"
      - "/readyz*"
      - "/livez*"
  # Don't log watch operations
  - level: None
    verbs: ["watch"]
  # Log Secret changes at Metadata level to avoid dumping sensitive token text
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
  # Log pod modifications with full request and response bodies
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods"]
    verbs: ["create", "update", "patch", "delete"]
  # Default fallback
  - level: Metadata
```

2. Enable flags in `/etc/kubernetes/manifests/kube-apiserver.yaml`:
```yaml
- --audit-policy-file=/etc/kubernetes/audit/policy.yaml
- --audit-log-path=/var/log/kubernetes/audit.log
- --audit-log-maxage=10
- --audit-log-maxbackup=5
- --audit-log-maxsize=100
```
Remember to add the necessary `volumeMounts` and `volumes` in the manifest for `/etc/kubernetes/audit/policy.yaml` and `/var/log/kubernetes/`.

---

## 🔒 Domain 4: Cluster Hardening (15%)

### 4.1 Securing the API Server
Audit these crucial flags in `/etc/kubernetes/manifests/kube-apiserver.yaml`:
- `--anonymous-auth=false` (Disable unauthenticated access)
- `--profiling=false` (Prevent profiling data leaks)
- `--enable-admission-plugins=NodeRestriction,PodSecurity`
- `--kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt` (Verify kubelet certs)

### 4.2 Restricting ServiceAccount Tokens
By default, Kubernetes mounts service account tokens inside every container:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: read-only-sa
automountServiceAccountToken: false   # Disable token auto-injection
```
Or directly on a specific Pod:
```yaml
spec:
  automountServiceAccountToken: false
```

---

## ⚙️ Domain 5: System Hardening (15%)

### 5.1 AppArmor Profiles
AppArmor restricts filesystem and capability privileges on worker nodes.

1. Parse & load profile on target node:
```bash
sudo apparmor_parser -q /etc/apparmor.d/k8s-custom-profile
sudo aa-status | grep k8s-custom-profile
```

2. Assign to Pod (Kubernetes 1.30+ uses container securityContext `appArmorProfile`):
```yaml
spec:
  containers:
  - name: my-container
    image: nginx
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: k8s-custom-profile
```

### 5.2 Seccomp (Secure Computing Mode)
Restricts system calls made by container processes:
- Default profiles directory: `/var/lib/kubelet/seccomp/`
- Enforce built-in runtime default profile:
```yaml
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
```
Custom profile located at `/var/lib/kubelet/seccomp/profiles/deny-chmod.json`:
```yaml
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/deny-chmod.json
```

---

## 📋 Domain 6: Cluster Setup (10%)

### 6.1 CIS Benchmark Automation with `kube-bench`
```bash
# Run CIS audit on master/control plane
kube-bench run --targets master

# Run CIS audit on worker node
kube-bench run --targets node

# Review failed tests and remediate flags in /etc/kubernetes/manifests/*.yaml
```

### 6.2 Zero-Trust Default Deny NetworkPolicy
Always enforce default deny for both Ingress and Egress:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

---

## ⚡ CKS Exam Survival Tactics

1. **Static Pod Manifest safety**: Always backup `/etc/kubernetes/manifests/` to `/tmp/` before touching any control plane file. One indentation mistake kills the API server.
2. **Docs verification**: Keep tabs open to Falco rules syntax, AppArmor pod annotations/fields, and kube-apiserver parameters.
3. **Double verify kubelet health**: When changing static pod manifests, run `crictl ps` or `sudo journalctl -u kubelet -n 20` to verify pod restart status.


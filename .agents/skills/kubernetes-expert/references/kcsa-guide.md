# KCSA – Kubernetes and Cloud Security Associate Reference Guide

> **Exam Format:** Multiple-choice · 90 minutes · 60 questions · 75% passing score
> **Certification Body:** CNCF / Linux Foundation
> **Validity:** 3 years

---

## Domain 1: Kubernetes Cluster Component Security (22%)

### 1.1 API Server Security

The **kube-apiserver** is the most critical component to secure — it's the gateway to all cluster operations.

**Hardening measures:**
- Enable TLS for all API traffic (default on port 6443)
- Disable anonymous authentication (`--anonymous-auth=false`)
- Enable audit logging (`--audit-policy-file`, `--audit-log-path`)
- Restrict access with RBAC (`--authorization-mode=RBAC,Node`)
- Use admission controllers (`--enable-admission-plugins`)
- Disable insecure port (`--insecure-port=0` — removed in 1.24+)
- Enable encryption at rest for Secrets (`--encryption-provider-config`)
- Limit API access via network policies and firewalls
- Use OIDC or webhook token authentication for users
- Set `--profiling=false` to disable profiling endpoint

**API Request Flow:**
```
Client → Authentication → Authorization → Admission Control → Validation → etcd
```

### 1.2 etcd Security

etcd stores **all cluster state**, including Secrets — it's the highest-value target.

**Hardening measures:**
- Enable TLS for client-to-server and peer-to-peer communication
  - `--cert-file`, `--key-file` (server cert)
  - `--peer-cert-file`, `--peer-key-file` (peer cert)
  - `--trusted-ca-file`, `--peer-trusted-ca-file`
- Restrict access: only the API server should communicate with etcd
- Enable encryption at rest for sensitive data (Secrets)
- Use client certificate authentication (`--client-cert-auth=true`)
- Run etcd on dedicated nodes (not shared with other workloads)
- Regular backups with `etcdctl snapshot save`
- Restrict filesystem permissions on etcd data directory
- Limit network access to etcd ports (2379, 2380)

**Encryption at rest configuration:**
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
          secret: <base64-encoded-secret>
    - identity: {}   # Fallback for reading unencrypted data
```

### 1.3 Controller Manager Security

**Hardening measures:**
- Enable TLS serving (`--tls-cert-file`, `--tls-private-key-file`)
- Set `--profiling=false`
- Use unique service account credentials per controller (`--use-service-account-credentials=true`)
- Bind to localhost for health/metrics endpoints (`--bind-address=127.0.0.1`)
- Set `--terminated-pod-gc-threshold` to clean up terminated pods
- Rotate service account signing keys

### 1.4 Scheduler Security

**Hardening measures:**
- Enable TLS for the scheduler's serving endpoint
- Set `--profiling=false`
- Bind to localhost (`--bind-address=127.0.0.1`)
- Use authentication and authorization for the scheduler's API

### 1.5 Worker Node Security

#### kubelet Security
- Disable anonymous authentication (`--anonymous-auth=false`)
- Enable webhook authorization (`--authorization-mode=Webhook`)
- Set `--read-only-port=0` to disable the read-only port (10255)
- Rotate kubelet certificates (`--rotate-certificates=true`)
- Enable TLS (`--tls-cert-file`, `--tls-private-key-file`)
- Protect the kubelet API on port 10250
- Set `--protect-kernel-defaults=true`
- Implement `NodeRestriction` admission plugin to limit kubelet API access

#### Container Runtime Security
- Keep the runtime (containerd/CRI-O) updated
- Use read-only root filesystems where possible
- Run containers as non-root users
- Use seccomp profiles to restrict system calls
- Use AppArmor or SELinux for mandatory access control
- Limit container capabilities (drop `ALL`, add only needed)
- Consider gVisor or Kata Containers for stronger isolation

#### kube-proxy Security
- Use IPVS mode for better performance and security at scale
- Restrict access to kube-proxy metrics endpoint
- Keep kube-proxy configuration secured and version-current

### 1.6 Networking Security

- Use a CNI plugin that supports Network Policies (Calico, Cilium)
- Encrypt pod-to-pod traffic (WireGuard with Cilium/Calico, or service mesh mTLS)
- Segment cluster networks (control plane, worker, etcd on separate subnets)
- Use private API server endpoints (not publicly accessible)
- Implement ingress controllers with TLS termination
- Use DNS policies to restrict external DNS resolution

### 1.7 Storage and Volume Security

- Limit `hostPath` volumes (or disable via admission control)
- Use ReadOnly volume mounts where possible (`readOnly: true`)
- Encrypt PersistentVolumes at the storage layer
- Use storage classes with appropriate reclaim policies (`Delete` to prevent data leaks)
- Restrict which Pods can use which storage classes via RBAC
- Use volume snapshots for backup and recovery
- Avoid `emptyDir` with `medium: Memory` for sensitive data (visible in `/proc`)

---

## Domain 2: Kubernetes Security Fundamentals (22%)

### 2.1 Authentication

Kubernetes has **no built-in user management**. Authentication is handled externally.

**Authentication methods:**
| Method | Description | Use Case |
|---|---|---|
| **X.509 Client Certificates** | Client presents a certificate signed by the cluster CA | Service accounts, initial setup |
| **Bearer Tokens** | Static token or service account token | Service account authentication |
| **OIDC (OpenID Connect)** | Integration with identity providers (Keycloak, Okta, Azure AD) | User authentication (recommended) |
| **Webhook Token** | External service validates tokens | Custom authentication |
| **Bootstrap Tokens** | Short-lived tokens for node bootstrapping | kubeadm node join |

**Service Accounts:**
- Kubernetes-managed identities for Pods
- Each namespace has a `default` service account
- Tokens mounted automatically (disable with `automountServiceAccountToken: false`)
- K8s 1.24+: Tokens are short-lived, bound tokens (no longer auto-created as Secrets)
- Best practice: Create dedicated service accounts per workload with minimal permissions

### 2.2 Authorization (RBAC)

**Role-Based Access Control (RBAC)** is the primary authorization mechanism.

**RBAC Components:**

| Resource | Scope | Purpose |
|---|---|---|
| **Role** | Namespace | Defines permissions within a namespace |
| **ClusterRole** | Cluster | Defines permissions cluster-wide or on cluster-scoped resources |
| **RoleBinding** | Namespace | Binds a Role/ClusterRole to subjects in a namespace |
| **ClusterRoleBinding** | Cluster | Binds a ClusterRole to subjects cluster-wide |

**Subjects:** Users, Groups, ServiceAccounts

```yaml
# Role: allows reading pods in the "production" namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
# RoleBinding: binds the role to a user
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: production
subjects:
- kind: User
  name: jane
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

**RBAC Best Practices:**
- Follow the **principle of least privilege**
- Use namespace-scoped Roles over ClusterRoles when possible
- Avoid `cluster-admin` ClusterRoleBinding for regular users
- Audit RBAC permissions with `kubectl auth can-i`
- Avoid wildcard (`*`) permissions
- Regularly review and clean up unused bindings
- Use `kubectl auth can-i --list` to enumerate permissions

**Other Authorization Modes:**
- **Node**: Authorizes kubelet API requests (use with RBAC)
- **ABAC**: Attribute-Based Access Control (legacy, harder to manage)
- **Webhook**: External authorization service

### 2.3 Pod Security Standards (PSS) / Pod Security Admission (PSA)

Replaced the deprecated PodSecurityPolicy (PSP) in Kubernetes v1.25.

**Three security levels:**

| Level | Description | Key Restrictions |
|---|---|---|
| **Privileged** | Unrestricted (no restrictions) | No restrictions applied |
| **Baseline** | Minimally restrictive, prevents known privilege escalation | No hostNetwork, hostPID, hostIPC; no privileged containers; restricted volume types |
| **Restricted** | Heavily restricted, follows hardening best practices | Must run as non-root; drop ALL capabilities; read-only root filesystem recommended; restrictive seccomp profile required |

**Enforcement modes:**

| Mode | Behavior |
|---|---|
| **enforce** | Rejects Pods that violate the policy |
| **audit** | Allows but logs violations in audit log |
| **warn** | Allows but returns a warning to the user |

**Applied via namespace labels:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/enforce-version: latest
```

### 2.4 Admission Controllers

**Admission controllers** intercept requests to the API server after authentication and authorization, but before persistence.

**Types:**
- **Mutating**: Can modify the request (run first)
- **Validating**: Can accept or reject the request (run second)

**Key built-in admission controllers:**

| Controller | Purpose |
|---|---|
| **NamespaceLifecycle** | Prevents operations in non-existent or terminating namespaces |
| **LimitRanger** | Enforces resource limits per namespace |
| **ResourceQuota** | Enforces resource quotas per namespace |
| **ServiceAccount** | Automates service account integration |
| **NodeRestriction** | Limits kubelet to modify only its own Node and Pods |
| **PodSecurity** | Enforces Pod Security Standards |
| **MutatingAdmissionWebhook** | Calls external webhooks to mutate resources |
| **ValidatingAdmissionWebhook** | Calls external webhooks to validate resources |

**External policy engines (via webhooks):**
- **OPA/Gatekeeper** (CNCF Graduated): General-purpose policy engine using Rego language
- **Kyverno** (CNCF Incubating): Kubernetes-native policy engine using YAML policies
- **Kubewarden**: Policy engine using WebAssembly (Wasm)

### 2.5 Network Policies

Network Policies are essential for implementing microsegmentation.

**Default behavior:** Without any Network Policy, all ingress and egress traffic is allowed.

**Key concepts:**
- Policies are **additive** — they combine but cannot deny explicitly (only allow)
- A Pod is **isolated** for a traffic direction once any policy selects it for that direction
- Unselected traffic (not covered by any rule) is **denied** for isolated Pods

**Default deny all ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
spec:
  podSelector: {}    # Selects ALL pods in namespace
  policyTypes:
  - Ingress          # No ingress rules = deny all incoming
```

**Default deny all egress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress           # No egress rules = deny all outgoing
```

**Best practices:**
- Start with default deny policies in each namespace
- Explicitly allow only required traffic
- Use namespace selectors for cross-namespace policies
- Test policies before applying in production (use `audit` mode with CNI tools)
- Remember: Network Policies require a CNI plugin that supports them

### 2.6 Secrets Management

**Built-in Kubernetes Secrets limitations:**
- Base64 encoded (not encrypted)
- Stored unencrypted in etcd by default
- Accessible to anyone with RBAC permissions to read Secrets
- Visible in Pod specs, environment variables, and logs

**Hardening Secrets:**
1. Enable **encryption at rest** (EncryptionConfiguration with AES-CBC or KMS)
2. Enable **RBAC** to restrict Secret access
3. Use **external secret managers**: HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager
4. Use **Secrets Store CSI Driver** to mount external secrets as volumes
5. Avoid mounting Secrets as environment variables (prefer volume mounts — less exposure in logs and process listings)
6. Disable automatic service account token mounting when not needed
7. Use short-lived tokens (bound service account tokens)

**External Secrets Operator:**
- Syncs secrets from external providers into Kubernetes Secrets
- Supports Vault, AWS, Azure, GCP, and many more
- Keeps secrets in sync with the external source

### 2.7 Audit Logging

Kubernetes audit logging records all requests to the API server.

**Audit stages:**
| Stage | When |
|---|---|
| **RequestReceived** | When the request is first received |
| **ResponseStarted** | After response headers sent (long-running only) |
| **ResponseComplete** | After response body is sent |
| **Panic** | When a panic occurs |

**Audit levels:**
| Level | What's Logged |
|---|---|
| **None** | Don't log |
| **Metadata** | Request metadata only (user, timestamp, resource, verb) |
| **Request** | Metadata + request body |
| **RequestResponse** | Metadata + request body + response body |

**Audit policy example:**
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log Secret access at RequestResponse level
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]
# Log everything else at Metadata level
- level: Metadata
```

**Audit backends:**
- **Log**: Write to files (JSON format)
- **Webhook**: Send to external service
- Integration with SIEM tools (Splunk, Elasticsearch, Datadog)

---

## Domain 3: Kubernetes Threat Model (16%)

### 3.1 Trust Boundaries

Trust boundaries in a Kubernetes cluster define where trust changes:

```
┌─────────────────────────────────────────────────┐
│                    Internet                      │
├─────────────────────────────────────────────────┤  ← External boundary
│              Ingress / Load Balancer             │
├─────────────────────────────────────────────────┤  ← Cluster boundary
│  ┌──────────────────┐  ┌──────────────────────┐ │
│  │   Control Plane   │  │    Worker Nodes       │ │
│  │  ┌──────────────┐ │  │  ┌────────────────┐  │ │
│  │  │  API Server   │ │  │  │  Namespace A   │  │ │
│  │  │  etcd         │ │  │  │  ┌──────────┐  │  │ │
│  │  │  Scheduler    │ │  │  │  │ Pod / Cnt │  │  │ │  ← Pod boundary
│  │  │  Ctrl Mgr     │ │  │  │  └──────────┘  │  │ │
│  │  └──────────────┘ │  │  ├────────────────┤  │ │  ← Namespace boundary
│  └──────────────────┘  │  │  Namespace B   │  │ │
│                          │  └────────────────┘  │ │
│                          └──────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Key trust boundaries:**
1. **External → Cluster**: Ingress controllers, load balancers, API server access
2. **Cluster → Control Plane**: Only authorized components access control plane
3. **Namespace → Namespace**: RBAC, Network Policies provide isolation
4. **Pod → Pod**: Network Policies control east-west traffic
5. **Container → Host**: Container isolation, seccomp, AppArmor/SELinux

### 3.2 Data Flow Security

**Data in transit:**
- API server communication: TLS
- etcd communication: mTLS
- Pod-to-pod: CNI encryption (WireGuard) or service mesh mTLS
- Ingress: TLS termination at ingress controller

**Data at rest:**
- etcd encryption at rest (EncryptionConfiguration)
- PersistentVolume encryption (cloud provider or CSI driver)
- Secret encryption via KMS provider

### 3.3 Attack Vectors

#### Network Attacks
| Attack | Description | Mitigation |
|---|---|---|
| **Man-in-the-Middle** | Intercepting traffic between components | TLS/mTLS everywhere |
| **Pod-to-Pod lateral movement** | Compromised pod accesses other pods | Network Policies, service mesh |
| **DNS spoofing** | Redirecting service discovery | DNSSEC, encrypted DNS, Network Policies |
| **Metadata service attack** | Accessing cloud metadata (169.254.169.254) | Network Policies blocking metadata IP, use workload identity |
| **ARP spoofing** | Layer 2 attacks within the cluster | CNI-level protections, network segmentation |

#### Privilege Escalation
| Attack | Description | Mitigation |
|---|---|---|
| **Container breakout** | Escaping container to host | No privileged containers, seccomp, AppArmor, minimal capabilities |
| **Service account token abuse** | Using mounted SA token for lateral movement | Disable auto-mounting, use bound tokens, least-privilege RBAC |
| **Host mount exploitation** | Accessing host filesystem via hostPath | Restrict hostPath via PSA/PSS, admission controllers |
| **Writable /proc and /sys** | Kernel parameter manipulation | Read-only root FS, drop capabilities, restrict proc mount |
| **CAP_SYS_ADMIN abuse** | Near-root access inside container | Drop ALL capabilities, add only needed |

#### Malicious Code Execution
| Attack | Description | Mitigation |
|---|---|---|
| **Supply chain compromise** | Malicious base images or dependencies | Image scanning, signing, SBOM, trusted registries |
| **Crypto mining** | Unauthorized workloads consuming resources | Resource quotas, runtime security monitoring, Network Policies |
| **Reverse shell** | Outbound connection from compromised pod | Egress Network Policies, runtime monitoring |
| **Malicious admission webhook** | Intercepting/modifying all API requests | Secure webhook configuration, audit logging |

#### Denial of Service (DoS)
| Attack | Description | Mitigation |
|---|---|---|
| **Resource exhaustion** | Pod consuming excessive CPU/memory | Resource requests/limits, LimitRange, ResourceQuota |
| **Fork bomb** | Creating excessive processes | PID limits (`pids` cgroup), resource limits |
| **API server flooding** | Overwhelming the API server | Rate limiting, API priority and fairness, RBAC |
| **etcd exhaustion** | Too many objects or watch requests | Resource quotas, monitoring, etcd size limits |
| **Noisy neighbor** | Co-located workload affecting others | Scheduling constraints, resource guarantees, node isolation |

### 3.4 STRIDE Threat Model Applied to Kubernetes

| Threat | Kubernetes Context | Key Mitigations |
|---|---|---|
| **Spoofing** | Impersonating users, services, or nodes | Strong authentication (OIDC, certs), service mesh mTLS |
| **Tampering** | Modifying data in transit or at rest, image tampering | TLS, encryption at rest, image signing, admission control |
| **Repudiation** | Denying actions taken on the cluster | Audit logging, immutable logging infrastructure |
| **Information Disclosure** | Secret leakage, unauthorized data access | Encryption, RBAC, Network Policies, Secret management |
| **Denial of Service** | Resource exhaustion, API flooding | Quotas, limits, rate limiting, autoscaling |
| **Elevation of Privilege** | Container breakout, RBAC misconfiguration | PSA, least privilege, no root, admission controllers |

---

## Domain 4: Platform Security (16%)

### 4.1 Supply Chain Security

#### Container Image Security
- **Scan images** for vulnerabilities: Trivy, Grype, Snyk, Clair
- **Sign images** for integrity: Cosign (Sigstore project), Notary
- **Use minimal base images**: distroless, Alpine, scratch
- **Pin image digests** instead of tags (tags are mutable)
- **Use trusted registries**: Harbor, ECR, GCR, ACR with access controls
- **Multi-stage builds** to minimize attack surface

#### Software Bill of Materials (SBOM)
- Inventory of all components in a software artifact
- Formats: SPDX, CycloneDX
- Generate with: Syft, Trivy, Docker SBOM
- Enables vulnerability tracking and license compliance
- Required by many compliance frameworks

#### Image Signing and Verification
```bash
# Sign image with Cosign (Sigstore)
cosign sign --key cosign.key registry.example.com/app:v1.0

# Verify image signature
cosign verify --key cosign.pub registry.example.com/app:v1.0
```

**Enforce image signing with admission controllers:**
- Sigstore Policy Controller
- Kyverno with image verification policies
- OPA/Gatekeeper with external data

#### Build Pipeline Security
- Use **hermetic builds** (fully reproducible, no external dependencies at build time)
- Implement **SLSA framework** (Supply-chain Levels for Software Artifacts)
  - Level 1: Build process documented
  - Level 2: Hosted build service, basic provenance
  - Level 3: Hardened build platform, non-falsifiable provenance
  - Level 4: Hermetic, reproducible builds
- Scan dependencies for vulnerabilities
- Pin dependency versions

### 4.2 OS Hardening

**Host OS hardening for Kubernetes nodes:**
- Use minimal OS distributions (Bottlerocket, Flatcar, Talos, Ubuntu Core)
- Keep kernel and packages updated
- Disable unnecessary services and ports
- Configure firewall rules (only allow required traffic)
- Enable and configure SELinux or AppArmor
- Set up unattended security updates
- Restrict SSH access (key-based only, no root login)
- Enable host-level audit logging (auditd)
- Use CIS Benchmarks for OS hardening

**Kernel hardening:**
- Enable **seccomp** (secure computing mode) profiles
- Use **AppArmor** (Ubuntu/Debian) or **SELinux** (RHEL/CentOS) profiles
- Restrict kernel module loading
- Enable kernel audit subsystem
- Configure sysctl parameters for security

**seccomp profile example (in Pod spec):**
```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault    # Use runtime's default seccomp profile
```

### 4.3 Cloud Provider Security

**Shared Responsibility Model:**
- **Cloud provider** manages: Physical infrastructure, hypervisor, managed control plane (in managed K8s)
- **Customer** manages: Worker node configuration, applications, RBAC, Network Policies, Secrets

**Cloud-specific security features:**
| Feature | AWS (EKS) | Azure (AKS) | GCP (GKE) |
|---|---|---|---|
| **Workload Identity** | IRSA | Workload Identity | Workload Identity Federation |
| **Network Isolation** | Security Groups, VPC | NSG, VNET | Firewall Rules, VPC |
| **Secret Management** | AWS Secrets Manager | Azure Key Vault | GCP Secret Manager |
| **Image Registry** | ECR | ACR | Artifact Registry |
| **Encryption** | KMS, EBS encryption | Azure Key Vault | Cloud KMS, CMEK |
| **Audit Logging** | CloudTrail | Azure Monitor | Cloud Audit Logs |

**Best practices:**
- Use **workload identity** instead of static cloud credentials
- Enable **VPC/VNET** private clusters (no public API endpoint)
- Use **managed encryption** (cloud KMS) for etcd and volumes
- Enable cloud-native **audit logging** alongside Kubernetes audit logs
- Rotate credentials and certificates regularly

---

## Domain 5: Overview of Cloud Native Security (14%)

### 5.1 The 4Cs of Cloud Native Security

Security in layers — each layer builds on the one below:

```
┌─────────────────────────────┐
│          Code               │  ← Application-level security
├─────────────────────────────┤
│        Container            │  ← Image scanning, minimal images, non-root
├─────────────────────────────┤
│         Cluster             │  ← RBAC, PSA, Network Policies, audit
├─────────────────────────────┤
│          Cloud              │  ← Infrastructure, network, IAM
└─────────────────────────────┘
```

#### Cloud (Infrastructure)
- Secure the underlying infrastructure (VPC, IAM, firewalls)
- Enable encryption at the infrastructure level
- Use private endpoints for managed services
- Implement network segmentation

#### Cluster
- RBAC and least-privilege access
- Pod Security Standards
- Network Policies
- Audit logging
- Admission controllers
- etcd encryption at rest
- Regular upgrades

#### Container
- Use minimal, trusted base images
- Scan for vulnerabilities
- Sign and verify images
- Don't run as root
- Use read-only root filesystem
- Drop unnecessary capabilities

#### Code
- Secure coding practices (OWASP)
- Dependency scanning (SCA)
- Static Application Security Testing (SAST)
- Dynamic Application Security Testing (DAST)
- Input validation and output encoding
- Secrets management (never hardcode)

### 5.2 Cloud Native Security Principles

**Defense in Depth:**
- Multiple layers of security controls
- No single layer is solely responsible
- Failure of one layer doesn't compromise the system

**Principle of Least Privilege:**
- Grant only the minimum permissions needed
- Apply at every level: RBAC, capabilities, network, filesystem
- Regularly review and audit permissions

**Shift Left Security:**
- Integrate security early in the development lifecycle
- Scan code and images during CI/CD, not just in production
- Security as code: policies defined declaratively

**Separation of Concerns:**
- Namespace isolation for multi-tenancy
- Separate control plane and data plane
- Dedicated nodes for sensitive workloads

### 5.3 Zero-Trust Architecture

**Core principle:** "Never trust, always verify"

**Zero-trust in Kubernetes:**

| Principle | Implementation |
|---|---|
| **Verify identity** | mTLS between services (service mesh), OIDC for users |
| **Least-privilege access** | RBAC, minimal capabilities, Pod Security Standards |
| **Microsegmentation** | Network Policies, namespace isolation |
| **Encrypt everything** | TLS in transit, encryption at rest |
| **Continuous verification** | Runtime security monitoring, behavioral analysis |
| **Assume breach** | Audit logging, incident response plans, blast radius reduction |

**Service mesh role in zero-trust:**
- Automatic mTLS between all services
- Identity-based authorization policies
- Traffic encryption without application changes
- Observability for security monitoring

### 5.4 Immutable Infrastructure

**Principles:**
- Infrastructure components are never modified after deployment
- Changes are made by deploying new versions (replace, don't update)
- Configuration drift is eliminated

**In Kubernetes:**
- Use immutable container images (no `kubectl exec` for changes)
- Read-only root filesystems in containers
- GitOps for declarative, versioned infrastructure
- Rolling deployments replace pods rather than updating them
- Infrastructure as Code (Terraform, Pulumi, Crossplane)

**Benefits:**
- Predictable and reproducible deployments
- Easier debugging (known state)
- Reduced attack surface (no write access)
- Simplified rollback (redeploy previous version)

---

## Domain 6: Compliance and Security Frameworks (10%)

### 6.1 CIS Benchmarks for Kubernetes

The **Center for Internet Security (CIS)** provides detailed security benchmarks for Kubernetes.

**CIS Benchmark categories:**
1. **Control Plane Components** — API server, controller manager, scheduler, etcd
2. **Worker Nodes** — kubelet, container runtime, kube-proxy
3. **Policies** — RBAC, Pod Security, Network Policies, Secrets, general policies
4. **Managed Services** — Cloud-specific settings (EKS, AKS, GKE benchmarks)

**Running CIS Benchmarks:**
```bash
# Using kube-bench (Aqua Security, open source)
kube-bench run --targets master    # Check control plane
kube-bench run --targets node      # Check worker nodes
kube-bench run --targets policies  # Check policies

# Output formats
kube-bench run --json              # JSON output for automation
```

**kube-bench** maps directly to CIS Benchmark checks:
- **PASS**: Configuration meets the benchmark
- **FAIL**: Configuration does not meet the benchmark
- **WARN**: Requires manual verification
- **INFO**: Informational (no automated check)

**Key CIS Benchmark checks (examples):**
| ID | Check | Category |
|---|---|---|
| 1.1.1 | Ensure API server `--anonymous-auth` is not set to `true` | API Server |
| 1.2.6 | Ensure `--authorization-mode` includes `RBAC` | API Server |
| 2.1 | Ensure etcd `--client-cert-auth` is set to `true` | etcd |
| 4.1.1 | Ensure kubelet `--anonymous-auth` is set to `false` | Worker Node |
| 4.2.1 | Minimize the admission of privileged containers | Policies |
| 5.2.1 | Ensure RBAC is configured for least privilege | Policies |

### 6.2 Compliance Mapping

**Common compliance frameworks and Kubernetes controls:**

| Framework | Focus | Kubernetes Controls |
|---|---|---|
| **SOC 2** | Security, availability, integrity | RBAC, audit logging, encryption, access controls |
| **PCI DSS** | Payment card data security | Network segmentation, encryption, access controls, logging |
| **HIPAA** | Healthcare data privacy | Encryption at rest/transit, audit trails, access controls |
| **GDPR** | EU data protection | Data encryption, access controls, right to erasure |
| **NIST 800-53** | Federal information systems | Comprehensive security controls catalog |
| **ISO 27001** | Information security management | Risk assessment, security controls, continuous improvement |
| **FedRAMP** | Cloud security for US government | Based on NIST 800-53, continuous monitoring |

**Mapping Kubernetes to compliance controls:**
- **Access Control** → RBAC, authentication, admission controllers
- **Audit & Accountability** → Kubernetes audit logging, cloud audit logs
- **Data Protection** → Encryption at rest/in transit, Secrets management
- **Configuration Management** → GitOps, IaC, immutable infrastructure
- **Incident Response** → Runtime security monitoring, logging, alerting
- **Risk Assessment** → Vulnerability scanning, CIS benchmarks, penetration testing

### 6.3 Auditing Requirements

**What to audit:**
- All API server requests (especially for Secrets, RBAC, workloads)
- Pod creation/deletion/modification
- RBAC changes (Role, RoleBinding, ClusterRole, ClusterRoleBinding)
- Namespace creation/deletion
- Service account token creation
- Admission controller decisions
- Node registration/deregistration

**Audit log management:**
- Centralize logs in a SIEM or log aggregation platform
- Set retention policies (typically 90-365 days depending on compliance)
- Ensure log integrity (immutable storage, tamper detection)
- Set up alerts on suspicious activities
- Regular audit log review (manual and automated)

**Compliance audit tools:**
| Tool | Purpose |
|---|---|
| **kube-bench** | CIS Benchmark compliance checks |
| **kube-hunter** | Penetration testing for Kubernetes clusters |
| **Polaris** | Configuration validation and best practices |
| **Kubescape** | Risk analysis, compliance, and misconfiguration scanning (NSA/CISA, CIS, MITRE) |
| **Falco** (CNCF Incubating) | Runtime security monitoring and threat detection |
| **Trivy** | Vulnerability scanner (images, IaC, SBOM, Kubernetes) |
| **Starboard / Trivy Operator** | Kubernetes-native security reporting |

---

## Practice Questions

### Domain 1: Kubernetes Cluster Component Security

**Q1.** Which component should be the ONLY one allowed to communicate directly with etcd?

A) kubelet
B) kube-scheduler
C) kube-apiserver
D) kube-controller-manager

**Answer: C) kube-apiserver** — Only the API server should communicate with etcd. All other components interact with the cluster state through the API server.

---

**Q2.** Which kubelet flag should be set to prevent anonymous access?

A) `--read-only-port=0`
B) `--anonymous-auth=false`
C) `--authorization-mode=RBAC`
D) `--protect-kernel-defaults=true`

**Answer: B) `--anonymous-auth=false`** — This disables unauthenticated access to the kubelet API. `--read-only-port=0` is also important but addresses a different issue (disabling the unauthenticated read-only port).

---

**Q3.** Encryption at rest for Kubernetes Secrets is configured via:

A) A Pod Security Standard
B) A Network Policy
C) An EncryptionConfiguration resource referenced by the API server
D) The kubelet configuration

**Answer: C) An EncryptionConfiguration resource** — The API server flag `--encryption-provider-config` points to an EncryptionConfiguration that specifies how resources (like Secrets) should be encrypted in etcd.

---

**Q4.** Which flag should be set on the kube-controller-manager to ensure each controller uses its own credentials?

A) `--profiling=false`
B) `--use-service-account-credentials=true`
C) `--bind-address=127.0.0.1`
D) `--terminated-pod-gc-threshold=100`

**Answer: B) `--use-service-account-credentials=true`** — This ensures each controller uses a separate service account rather than sharing the controller manager's credentials.

---

### Domain 2: Kubernetes Security Fundamentals

**Q5.** In RBAC, which resource grants permissions at the cluster scope?

A) Role
B) ClusterRole
C) RoleBinding
D) ConfigMap

**Answer: B) ClusterRole** — A ClusterRole defines permissions at the cluster scope or on cluster-scoped resources. A Role is namespace-scoped.

---

**Q6.** Which Pod Security Standard level enforces running containers as non-root and dropping all capabilities?

A) Privileged
B) Baseline
C) Restricted
D) Hardened

**Answer: C) Restricted** — The Restricted level enforces running as non-root, dropping ALL capabilities, requiring a seccomp profile, and other strict security controls.

---

**Q7.** What happens when a Network Policy selects a Pod for ingress but defines no ingress rules?

A) All ingress traffic is allowed
B) All ingress traffic is denied
C) Only DNS traffic is allowed
D) Only traffic from the same namespace is allowed

**Answer: B) All ingress traffic is denied** — When a Pod is selected by a Network Policy for a given direction but no rules are defined for that direction, all traffic in that direction is denied.

---

**Q8.** Which admission controller limits kubelets to only modifying their own Node objects and Pods?

A) PodSecurity
B) ResourceQuota
C) NodeRestriction
D) LimitRanger

**Answer: C) NodeRestriction** — NodeRestriction limits kubelets to only modifying Node and Pod objects that are running on their own node, preventing a compromised node from affecting others.

---

**Q9.** Starting in Kubernetes 1.24, service account tokens are:

A) Created as long-lived Secrets automatically
B) Short-lived, bound tokens projected into Pods
C) No longer supported
D) Stored in etcd without encryption

**Answer: B) Short-lived, bound tokens projected into Pods** — K8s 1.24+ uses bound service account tokens that are time-limited and audience-bound, improving security over the old long-lived Secret-based tokens.

---

**Q10.** Which audit level captures both the request and response body?

A) None
B) Metadata
C) Request
D) RequestResponse

**Answer: D) RequestResponse** — The RequestResponse level logs metadata, the request body, and the response body, providing the most detailed audit information.

---

### Domain 3: Kubernetes Threat Model

**Q11.** A compromised Pod attempts to access the cloud provider's metadata service at 169.254.169.254. What is the best mitigation?

A) Enable RBAC
B) Apply a Network Policy blocking egress to 169.254.169.254/32
C) Set a resource limit
D) Use a Deployment instead of a Pod

**Answer: B) Apply a Network Policy** — A Network Policy that blocks egress to the cloud metadata IP (169.254.169.254) prevents compromised pods from accessing instance metadata and cloud credentials.

---

**Q12.** Which attack vector involves a container escaping its isolation to access the host system?

A) DNS spoofing
B) Container breakout
C) Man-in-the-Middle
D) API server flooding

**Answer: B) Container breakout** — A container breakout occurs when a container exploits a vulnerability to escape its isolation boundaries and access the underlying host.

---

**Q13.** In the STRIDE threat model applied to Kubernetes, what mitigates "Repudiation" threats?

A) Network Policies
B) RBAC
C) Audit logging
D) Pod Security Standards

**Answer: C) Audit logging** — Audit logging ensures all actions are recorded and cannot be denied (repudiated). It provides an immutable record of who did what and when.

---

**Q14.** Which of the following is NOT a direct mitigation for privilege escalation in containers?

A) Dropping all Linux capabilities
B) Running as non-root
C) Using a LoadBalancer Service
D) Applying a seccomp profile

**Answer: C) Using a LoadBalancer Service** — LoadBalancer is a networking concept unrelated to container privilege escalation. The other options all directly restrict container privileges.

---

### Domain 4: Platform Security

**Q15.** What is the purpose of a Software Bill of Materials (SBOM)?

A) To encrypt container images
B) To provide an inventory of all components in a software artifact
C) To enforce network policies
D) To configure RBAC permissions

**Answer: B) To provide an inventory of all components** — An SBOM lists all components, libraries, and dependencies in a software artifact, enabling vulnerability tracking and compliance.

---

**Q16.** Which tool is commonly used to sign container images in the Sigstore ecosystem?

A) Trivy
B) Cosign
C) kube-bench
D) Falco

**Answer: B) Cosign** — Cosign is part of the Sigstore project and is used to sign, verify, and store container image signatures.

---

**Q17.** In the Shared Responsibility Model for managed Kubernetes (e.g., EKS, GKE, AKS), who is responsible for configuring RBAC?

A) The cloud provider
B) The customer
C) The Kubernetes community
D) Both the cloud provider and customer equally

**Answer: B) The customer** — In managed Kubernetes services, the cloud provider manages the control plane infrastructure, but RBAC configuration, Network Policies, and application security are the customer's responsibility.

---

**Q18.** Which SLSA level requires hermetic, reproducible builds?

A) Level 1
B) Level 2
C) Level 3
D) Level 4

**Answer: D) Level 4** — SLSA Level 4 requires hermetic (isolated, self-contained) and reproducible builds with the strongest provenance guarantees.

---

### Domain 5: Overview of Cloud Native Security

**Q19.** In the 4Cs security model, which layer is the outermost?

A) Code
B) Container
C) Cluster
D) Cloud

**Answer: D) Cloud** — The 4Cs from outermost to innermost are: Cloud → Cluster → Container → Code. Each inner layer builds on the security of the outer layers.

---

**Q20.** Which principle states "never trust, always verify"?

A) Defense in Depth
B) Least Privilege
C) Zero Trust
D) Separation of Concerns

**Answer: C) Zero Trust** — Zero Trust architecture assumes no implicit trust based on network location or identity; every request must be authenticated and authorized.

---

**Q21.** Immutable infrastructure in Kubernetes means:

A) Containers cannot be restarted
B) Components are replaced rather than modified in place
C) RBAC permissions cannot be changed
D) Network Policies are permanent

**Answer: B) Components are replaced rather than modified** — Immutable infrastructure means changes are made by deploying new versions, not by modifying existing components. This ensures consistency and predictability.

---

**Q22.** "Shift Left Security" means:

A) Moving security controls to the leftmost namespace
B) Integrating security testing early in the development lifecycle
C) Shifting security responsibilities to the development team exclusively
D) Using left-aligned YAML in manifests

**Answer: B) Integrating security testing early** — Shift Left means incorporating security practices earlier in the SDLC (development, CI) rather than only at deployment or runtime.

---

### Domain 6: Compliance and Security Frameworks

**Q23.** Which tool runs CIS Benchmark checks against a Kubernetes cluster?

A) kube-hunter
B) kube-bench
C) kubectl
D) Helm

**Answer: B) kube-bench** — kube-bench (by Aqua Security) is an open-source tool that runs the CIS Kubernetes Benchmark checks against your cluster.

---

**Q24.** Falco is primarily used for:

A) Container image scanning
B) Runtime security monitoring and threat detection
C) CIS Benchmark compliance
D) RBAC policy management

**Answer: B) Runtime security monitoring** — Falco (CNCF Incubating) detects anomalous activity at runtime by monitoring system calls and Kubernetes audit events.

---

**Q25.** Which compliance framework specifically addresses payment card data security?

A) HIPAA
B) SOC 2
C) PCI DSS
D) GDPR

**Answer: C) PCI DSS** — The Payment Card Industry Data Security Standard (PCI DSS) specifically governs the security of payment card data.

---

**Q26.** Kubernetes audit logs should ideally be stored:

A) Only on the API server node's local filesystem
B) In a centralized, immutable log aggregation platform
C) In a ConfigMap within the cluster
D) Only in etcd

**Answer: B) In a centralized, immutable log aggregation platform** — Audit logs should be forwarded to a centralized system (SIEM) with immutable storage to prevent tampering and ensure availability.

---

## Quick Reference: Key Security Facts for Exam Day

| Topic | Key Fact |
|---|---|
| **API Server auth** | `--anonymous-auth=false`, use OIDC or certs |
| **etcd** | TLS + client cert auth + encryption at rest, only API server access |
| **kubelet** | `--anonymous-auth=false`, `--authorization-mode=Webhook`, `--read-only-port=0` |
| **Secrets** | Base64 encoded (NOT encrypted) by default; enable EncryptionConfiguration |
| **RBAC** | Principle of least privilege; avoid wildcard permissions and cluster-admin |
| **PSA levels** | Privileged → Baseline → Restricted (most secure) |
| **PSA modes** | enforce, audit, warn |
| **Network Policies** | Default allow-all; selecting a Pod isolates it; rules are additive |
| **Admission controllers** | Mutating runs first, then Validating |
| **4Cs** | Cloud → Cluster → Container → Code (outer to inner) |
| **Zero Trust** | Never trust, always verify; mTLS, identity-based access |
| **CIS Benchmark tool** | kube-bench |
| **Runtime security** | Falco (CNCF Incubating) |
| **Image signing** | Cosign (Sigstore) |
| **Image scanning** | Trivy, Grype, Snyk, Clair |
| **SBOM formats** | SPDX, CycloneDX |
| **SLSA Level 4** | Hermetic, reproducible builds |
| **Audit levels** | None < Metadata < Request < RequestResponse |
| **SA tokens (1.24+)** | Short-lived, bound tokens (not long-lived Secrets) |
| **seccomp** | RuntimeDefault profile recommended |
| **Policy engines** | OPA/Gatekeeper (CNCF), Kyverno (CNCF), Kubewarden |
| **Compliance tools** | kube-bench, kube-hunter, Kubescape, Polaris, Falco, Trivy |

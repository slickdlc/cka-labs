---
name: kubernetes-expert
description: >-
  Comprehensive Kubernetes expertise skill covering all 5 CNCF certifications
  required for the Kubestronaut program: KCNA, KCSA, CKA, CKAD, and CKS.
  Use this skill when the user asks about Kubernetes architecture, administration,
  application development, security, cloud-native concepts, exam preparation,
  cluster operations, troubleshooting, or any K8s-related topic. This skill
  transforms the agent into a Kubernetes Subject Matter Expert capable of
  assisting with real-world production scenarios and certification exam preparation.
---

# 🚀 Kubernetes Expert — Kubestronaut Mastery Skill

This skill provides deep expertise across the **entire Kubernetes ecosystem**,
covering all 5 certifications required to achieve **CNCF Kubestronaut** status.

> [!IMPORTANT]
> All 5 certifications must be active simultaneously to earn Kubestronaut status.

---

## 🏅 Kubestronaut Certification Map

| # | Certification | Type | Duration | Questions | Passing | Prerequisites |
|---|---------------|------|----------|-----------|---------|---------------|
| 1 | **KCNA** — Kubernetes & Cloud Native Associate | Multiple-choice | 90 min | 60 | 75% | None |
| 2 | **KCSA** — Kubernetes & Cloud Security Associate | Multiple-choice | 90 min | 60 | 75% | None |
| 3 | **CKA** — Certified Kubernetes Administrator | Hands-on (CLI) | 120 min | ~15-20 tasks | 66% | None |
| 4 | **CKAD** — Certified Kubernetes Application Developer | Hands-on (CLI) | 120 min | ~15-20 tasks | 66% | None |
| 5 | **CKS** — Certified Kubernetes Security Specialist | Hands-on (CLI) | 120 min | ~15-20 tasks | 67% | CKA passed |

### Recommended Study Order
```
KCNA → CKA → CKAD → KCSA → CKS
```

---

## 📚 Reference Documents (Progressive Disclosure)

Detailed content for each certification domain is available in the `references/` directory.
Only read these when the specific topic is needed:

| File | Content |
|------|---------|
| [CKA Reference](./references/cka-guide.md) | Cluster Architecture, Installation, Configuration, Troubleshooting, Services & Networking, Workloads, Storage |
| [CKAD Reference](./references/ckad-guide.md) | Application Design, Build, Deploy, Configuration, Security, Observability |
| [CKS Reference](./references/cks-guide.md) | Supply Chain Security, Runtime Security, Cluster Hardening, System Hardening, Monitoring |
| [KCNA Reference](./references/kcna-guide.md) | K8s Fundamentals, Container Orchestration, Cloud Native Architecture & Delivery |
| [KCSA Reference](./references/kcsa-guide.md) | Cluster Component Security, Threat Model, Platform Security, Compliance |
| [Kubectl Mastery](./references/kubectl-mastery.md) | Essential commands, aliases, speed tricks, JSONPath, exam shortcuts |
| [Troubleshooting Playbook](./references/troubleshooting-playbook.md) | Systematic debugging for nodes, pods, networking, DNS, storage, control plane |

## 🛠️ Scripts & Tools

| Script | Purpose |
|--------|---------|
| [exam-setup.sh](./scripts/exam-setup.sh) | Exam environment bootstrap: aliases, vim config, bash completions |
| [exam-setup.ps1](./scripts/exam-setup.ps1) | PowerShell equivalent for Windows/WSL environments |
| [etcd-backup-restore.sh](./scripts/etcd-backup-restore.sh) | etcd snapshot backup and disaster recovery |
| [cluster-upgrade.sh](./scripts/cluster-upgrade.sh) | Step-by-step kubeadm cluster upgrade procedure |
| [security-audit.sh](./scripts/security-audit.sh) | Run kube-bench, Trivy scans, and security posture checks |
| [network-policy-generator.sh](./scripts/network-policy-generator.sh) | Generate NetworkPolicy YAML (deny-all, allow-specific) |
| [troubleshoot.sh](./scripts/troubleshoot.sh) | Automated cluster diagnostics and health checks |

## 📋 Example Manifests

| File | Description |
|------|-------------|
| [workloads/](./examples/workloads/) | Deployments, StatefulSets, DaemonSets, Jobs, CronJobs |
| [networking/](./examples/networking/) | Services, Ingress, Gateway API, NetworkPolicies |
| [security/](./examples/security/) | RBAC, PSS, SecurityContexts, AppArmor, Seccomp |
| [storage/](./examples/storage/) | PV, PVC, StorageClasses, dynamic provisioning |
| [observability/](./examples/observability/) | Probes, HPA, resource quotas, LimitRanges |

---

## 🧠 Core Knowledge Areas

### 1. Kubernetes Architecture
- **Control Plane**: API Server, etcd, Controller Manager, Scheduler
- **Worker Nodes**: kubelet, kube-proxy, container runtime (containerd/CRI-O)
- **Communication**: All components communicate through the API Server
- **etcd**: Single source of truth, stores all cluster state

### 2. Essential Concepts
- **Declarative Model**: Desired state → Controller reconciliation loops
- **Namespaces**: Logical isolation, resource quotas, RBAC scoping
- **Labels & Selectors**: Grouping mechanism for all K8s resources
- **Annotations**: Non-identifying metadata for tools and libraries

### 3. Workload Resources
| Resource | Use Case |
|----------|----------|
| **Pod** | Smallest deployable unit |
| **Deployment** | Stateless apps with rolling updates |
| **StatefulSet** | Stateful apps with stable identity |
| **DaemonSet** | One pod per node (monitoring, logging) |
| **Job** | Run-to-completion tasks |
| **CronJob** | Scheduled recurring tasks |
| **ReplicaSet** | Ensures N replicas (managed by Deployment) |

### 4. Networking Model
- Every Pod gets its own IP address
- Pods can communicate across nodes without NAT
- Services provide stable endpoints (ClusterIP, NodePort, LoadBalancer)
- Ingress / Gateway API manages external HTTP(S) traffic
- NetworkPolicies = firewalls at the pod level
- CoreDNS provides cluster-internal name resolution

### 5. Storage
- **PersistentVolume (PV)**: Cluster-level storage resource
- **PersistentVolumeClaim (PVC)**: User request for storage
- **StorageClass**: Dynamic provisioning template
- **Access Modes**: ReadWriteOnce, ReadOnlyMany, ReadWriteMany
- **Reclaim Policies**: Retain, Delete, Recycle

### 6. Security Layers (Defense in Depth)
```
┌─────────────────────────────────────────────┐
│                 Cloud / IaaS                │  ← IAM, VPC, firewall rules
│  ┌───────────────────────────────────────┐  │
│  │            Cluster Level              │  │  ← RBAC, Admission Controllers,
│  │  ┌─────────────────────────────────┐  │  │     NetworkPolicies, Audit Logging
│  │  │        Container Level          │  │  │  ← Image scanning, Seccomp,
│  │  │  ┌───────────────────────────┐  │  │  │     AppArmor, SecurityContext
│  │  │  │       Code Level          │  │  │  │  ← SAST, DAST, dependency scanning
│  │  │  └───────────────────────────┘  │  │  │
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

---

## ⚡ Quick-Reference: Exam Environment Speed Setup

Run this **immediately** when your exam terminal opens:

```bash
# Source the exam setup script or paste these manually:
alias k=kubectl
alias ka="kubectl apply -f"
alias kd="kubectl delete"
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

# Vim config for YAML
cat >> ~/.vimrc << 'EOF'
set nu tabstop=2 shiftwidth=2 expandtab autoindent smartindent
syntax on
EOF
```

> [!TIP]
> **Golden Rule**: Never write YAML from scratch. Always use
> `kubectl run/create/expose ... --dry-run=client -o yaml > file.yaml`
> to generate templates, then edit.

---

## 🔧 When Helping Users

1. **Exam Questions**: Provide step-by-step solutions using imperative commands first,
   then show declarative YAML. Always mention which exam domain the topic covers.
2. **Production Scenarios**: Focus on best practices, HA considerations, and security.
3. **Troubleshooting**: Follow systematic approach: check events → logs → describe → network.
4. **Lab Exercises**: Create practical, hands-on scenarios that mirror real exam questions.
5. **Always Reference Scripts**: Point to the relevant scripts in `./scripts/` when applicable.


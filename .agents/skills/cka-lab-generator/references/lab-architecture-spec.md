# Architectural Specification for Reproducible CKA Labs

This document details the canonical structure, required components, and design patterns needed to build 100% reproducible and reliable practice labs for the **Certified Kubernetes Administrator (CKA)** exam across any playground environment (Kind, Minikube, K3s, Killer.sh, Killercoda, or multi-node Kubeadm clusters).

---

## 1. Required Components for a Complete CKA Lab

Beyond the problem statement, setup script, and validator, practical playground reliability requires additional components:

| Component | File | Required | Purpose |
| :--- | :--- | :---: | :--- |
| **Exam Problem Statement** | `question.md` | **Yes** | Strict CKA format: objective, constraints, resources, exact paths, no hints or spoilers. |
| **Setup Script** | `setup.sh` | **Yes** | Idempotently creates initial state, namespaces, broken resources (in troubleshooting), and prerequisites. |
| **Validation Script** | `validate.sh` | **Yes** | Evaluates technical criteria with functional and declarative tests. Returns exit 0 (passed) or exit 1 (failed). |
| **Cleanup Script** | `cleanup.sh` | **Yes** | Removes all lab artifacts to leave the cluster clean and reusable without rebooting nodes. |
| **Solution Guide** | `solution.md` | **Yes** | Step-by-step guide with high-speed imperative commands (`--dry-run=client -o yaml`) and architectural explanations. |
| **Structured Metadata** | `metadata.yaml` | **Yes** | CKA domain, exam percentage weight, estimated completion time, difficulty level, and index tags. |
| **Test Harness** | `test-lab.sh` | **Recommended** | Script validating the lab lifecycle: `setup -> test solution -> validate -> cleanup`. |

---

## 2. Playground Reproducibility Principles

To ensure a lab is reproducible across all environments (Linux, WSL2, GitHub Codespaces, Killercoda):

### A. Absolute Idempotency
- `setup.sh` must be able to run multiple consecutive times without failing or duplicating resources.
- If the student restarts the lab, `setup.sh` must clean up previous artifacts before recreating them.

### B. Namespace Isolation
- Every exercise must run in a dedicated namespace (e.g., `cka-lab-netpol`, `accounting`, `ingress-space`) unless the exercise explicitly targets cluster-scoped resources (e.g., `Node`, `ClusterRole`, `StorageClass`, `kube-system`).
- This prevents collisions with other labs or playground system services.

### C. No Fragile External Dependencies
- Use lightweight, officially maintained public images (`registry.k8s.io/pause`, `nginx:alpine`, `busybox:1.36`, `redis:alpine`).
- Avoid non-standard internet dependencies or tools not included in the standard exam environment (standard exams provide `bash`, `curl`, `jq`, `kubectl`, `vim`, `nano`, `systemctl`).

### D. Active Health Probing (Pre-flight checks)
- In `setup.sh`, actively wait for pods or scenario components to become Ready (`kubectl wait --for=condition=Ready ...`) before handing control to the student.

---

## 3. Component Specification Details

### 3.1. `question.md`
- **No Hints**: Do not instruct the student to use specific commands like `kubectl run --port...`. State the technical specification exactly as in official Linux Foundation exam questions.
- **Standard Format**:
  - Kubectl context (`kubectl config use-context ...` if applicable).
  - Explicit task specifications with exact names for Pods, Deployments, Services, Namespaces, Ports, Paths, and Selectors.

### 3.2. `setup.sh`
- Starts with `set -euo pipefail`.
- Cleans up existing resources using `kubectl delete ... --ignore-not-found=true`.
- Uses deterministic configurations.

### 3.3. `validate.sh`
- Starts with `set -uo pipefail`.
- Uses colorized terminal formatting (`[PASS]` and `[FAIL]`).
- Performs both declarative tests (`kubectl get ... -o jsonpath=...`) and functional checks (`curl`, `nslookup`, `wget`).
- Returns exit code 0 on complete success, exit code 1 on any failure.

### 3.4. `cleanup.sh`
- Restores altered cluster state.
- Deletes created namespaces with `--ignore-not-found=true --timeout=60s`.

### 3.5. `solution.md`
- Highlights high-speed command line techniques.
- Details the root cause of issues in troubleshooting tasks.

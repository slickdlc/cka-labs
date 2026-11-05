# Solution Guide: CKA 2025 Argo CD Helm Deployment

## 1. Quick Imperative Steps (CKA Exam Speed Run: ~3 minutes)

```bash
# Step 1: Add the official Argo CD Helm repository and update
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Step 2: Confirm Argo CD CRDs are already present in the cluster
kubectl get crd | grep argoproj

# Step 3: Render the Helm template with version 7.7.3, disabling CRDs, and save to /argo-helm.yaml
helm template argocd argo/argo-cd \
  --version 7.7.3 \
  --namespace argocd \
  --set crds.install=false > /argo-helm.yaml

# Step 4: Install Argo CD with the same version and CRD configuration
helm install argocd argo/argo-cd \
  --version 7.7.3 \
  --namespace argocd \
  --set crds.install=false
```

---

## 2. Detailed Technical Breakdown

### Step 1: Add Helm Repository
The official Argo project Helm charts repository is maintained at `https://argoproj.github.io/argo-helm`.
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
```
Verify the repo was registered correctly:
```bash
helm repo list
```

### Step 2: Verify Pre-installed CRDs
The scenario states that Argo CD CRDs have already been installed in the cluster. You can confirm them using `kubectl`:
```bash
kubectl get crds | grep -E "applications|applicationsets|appprojects"
```
Output:
```text
applications.argoproj.io      ...
applicationsets.argoproj.io   ...
appprojects.argoproj.io       ...
```

### Step 3: Generate Helm Template without CRDs
The `helm template` command renders chart templates locally without connecting to the Kubernetes API server or applying resources.
Key parameters required:
- `argocd`: Release name.
- `argo/argo-cd`: Chart reference `<repo-name>/<chart-name>`.
- `--version 7.7.3`: Specific chart version explicitly requested.
- `--namespace argocd`: Target namespace.
- `--set crds.install=false`: Disables CRD inclusion in the rendered manifest.
- `> /argo-helm.yaml`: Redirects stdout to root path `/argo-helm.yaml`.

```bash
helm template argocd argo/argo-cd \
  --version 7.7.3 \
  --namespace argocd \
  --set crds.install=false > /argo-helm.yaml
```

**Verification:**
Verify that no `CustomResourceDefinition` resources are present in the generated file:
```bash
grep -i "CustomResourceDefinition" /argo-helm.yaml
# (Must return empty)
```

Verify that standard Argo CD components exist in the generated manifest:
```bash
grep "kind: Deployment" /argo-helm.yaml -A 2
```

### Step 4: Install the Release via Helm
Deploy Argo CD into the cluster using the exact parameters defined in the prompt:
```bash
helm install argocd argo/argo-cd \
  --version 7.7.3 \
  --namespace argocd \
  --set crds.install=false
```

---

## 3. Post-Installation Verification

1. **Verify Helm Release Status:**
   ```bash
   helm list -n argocd
   ```
   *Expected Output:*
   ```text
   NAME    NAMESPACE  REVISION  UPDATED                   STATUS    CHART            APP VERSION
   argocd  argocd     1         2026-11-03 22:00:00...   deployed  argo-cd-7.7.3    v2.13.2
   ```

2. **Verify User Values Passed to Helm:**
   ```bash
   helm get values argocd -n argocd
   ```
   *Expected Output:*
   ```yaml
   USER-SUPPLIED VALUES:
   crds:
     install: false
   ```

3. **Verify Deployed Workloads:**
   ```bash
   kubectl get pods -n argocd
   kubectl get deployments -n argocd
   ```

---

## 4. Common Exam Pitfalls & Traps

| Pitfall | Consequence | Prevention |
|---|---|---|
| Omitting `--version 7.7.3` | Helm deploys the latest version (e.g. 7.8.x or 8.x), causing automatic test failure. | Always verify chart version with `helm list -n <ns>` or `helm search repo argo/argo-cd --versions`. |
| Omitting `--set crds.install=false` | Helm attempts to manage CRDs or template includes CRD manifests, violating the question constraints. | Always supply `--set crds.install=false` on both template and install commands. |
| Saving to relative path `./argo-helm.yaml` | The automated grader checks `/argo-helm.yaml` at filesystem root, failing the check. | Always check absolute path `/argo-helm.yaml` with leading slash. |
| Forgetting namespace `--namespace argocd` | Resources default to `default` namespace, failing namespace assertions. | Explicitly pass `--namespace argocd` to all Helm commands. |

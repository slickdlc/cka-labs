#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="argocd"
TEMPLATE_FILE="/argo-helm.yaml"

echo "=========================================================="
echo "=== [SETUP] Initializing CKA Lab: Argo CD Helm Deploy  ==="
echo "=========================================================="

# 1. Dependency checks
if ! command -v helm &>/dev/null; then
  echo "[SETUP] WARNING: 'helm' CLI is not found on PATH. Please ensure Helm v3 is installed."
fi

if ! command -v kubectl &>/dev/null; then
  echo "[SETUP] ERROR: 'kubectl' CLI is required but not found on PATH."
  exit 1
fi

# 2. Cleanup previous runs if existing
echo "[SETUP] Cleaning up existing Helm releases and target manifests..."
if command -v helm &>/dev/null; then
  helm uninstall argocd -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
  helm repo remove argo 2>/dev/null || true
fi

rm -f "$TEMPLATE_FILE"

echo "[SETUP] Resetting namespace '$NAMESPACE'..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true
kubectl create namespace "$NAMESPACE"

# 3. Pre-install Argo CD CustomResourceDefinitions (CRDs) as per requirements
echo "[SETUP] Pre-installing official Argo CD CRDs..."
cat << 'EOF' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: applications.argoproj.io
  labels:
    app.kubernetes.io/name: argo-cd
    app.kubernetes.io/part-of: argocd
spec:
  group: argoproj.io
  names:
    kind: Application
    listKind: ApplicationList
    plural: applications
    singular: application
    shortNames:
      - app
      - apps
  scope: Namespaced
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          x-kubernetes-preserve-unknown-fields: true
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: applicationsets.argoproj.io
  labels:
    app.kubernetes.io/name: argo-cd
    app.kubernetes.io/part-of: argocd
spec:
  group: argoproj.io
  names:
    kind: ApplicationSet
    listKind: ApplicationSetList
    plural: applicationsets
    singular: applicationset
    shortNames:
      - appset
      - appsets
  scope: Namespaced
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          x-kubernetes-preserve-unknown-fields: true
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: appprojects.argoproj.io
  labels:
    app.kubernetes.io/name: argo-cd
    app.kubernetes.io/part-of: argocd
spec:
  group: argoproj.io
  names:
    kind: AppProject
    listKind: AppProjectList
    plural: appprojects
    singular: appproject
    shortNames:
      - appproj
      - appprojs
  scope: Namespaced
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          x-kubernetes-preserve-unknown-fields: true
EOF

echo "[SETUP] Verifying CRDs are registered..."
kubectl wait --for=condition=Established crd/applications.argoproj.io crd/applicationsets.argoproj.io crd/appprojects.argoproj.io --timeout=30s

echo "=========================================================="
echo "=== [SETUP] Environment successfully initialized!     ==="
echo "=== Candidate may now begin the exercise.              ==="
echo "=========================================================="

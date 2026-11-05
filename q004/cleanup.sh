#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="argocd"
RELEASE_NAME="argocd"
TEMPLATE_FILE="/argo-helm.yaml"

echo "=========================================================="
echo "=== [CLEANUP] Tearing down CKA Lab: Argo CD Helm       ==="
echo "=========================================================="

echo "[CLEANUP] Uninstalling Helm release '$RELEASE_NAME' from namespace '$NAMESPACE'..."
if command -v helm &>/dev/null; then
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
  echo "[CLEANUP] Removing Helm repo 'argo'..."
  helm repo remove argo 2>/dev/null || true
fi

echo "[CLEANUP] Removing rendered template '$TEMPLATE_FILE'..."
rm -f "$TEMPLATE_FILE" 2>/dev/null || true

echo "[CLEANUP] Deleting namespace '$NAMESPACE'..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s 2>/dev/null || true

echo "[CLEANUP] Removing pre-installed Argo CD CRDs..."
kubectl delete crd \
  applications.argoproj.io \
  applicationsets.argoproj.io \
  appprojects.argoproj.io \
  --ignore-not-found=true --timeout=30s 2>/dev/null || true

echo "=========================================================="
echo "=== [CLEANUP] Completed. Playground is clean.          ==="
echo "=========================================================="

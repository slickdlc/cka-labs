#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="ecommerce-prod"

echo "[CLEANUP] Cleaning up lab resources in namespace '${NAMESPACE}'..."

# Delete namespace and all contained workloads
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "[CLEANUP] Deleting namespace '${NAMESPACE}'..."
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true --timeout=60s
fi

echo "[CLEANUP] Verification: Namespace '${NAMESPACE}' successfully removed."
echo "[CLEANUP] Lab environment cleanup complete."

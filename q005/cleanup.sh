#!/usr/bin/env bash
set -uo pipefail

NAMESPACE="default"
DEPLOY_NAME="wordpress"

echo "=========================================================="
echo "=== [CLEANUP] Cleaning up CKA Lab: WordPress Sidecar   ==="
echo "=========================================================="

echo "[CLEANUP] Deleting deployment '$DEPLOY_NAME' in namespace '$NAMESPACE'..."
kubectl delete deployment "$DEPLOY_NAME" -n "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true

echo "[CLEANUP] Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=wordpress -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

rm -f /tmp/wordpress-deploy*.yaml 2>/dev/null || true

echo "[CLEANUP] Lab cleanup complete."

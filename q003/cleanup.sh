#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mariadb"
PV_NAME="mariadb-pv"
DEPLOY_DIR="${HOME:-/root}"
DEPLOY_FILE="$DEPLOY_DIR/mariadb-deploy.yaml"
DATA_DIR="/data/mariadb"

echo "=========================================================="
echo "=== [CLEANUP] Tearing down CKA Lab: MariaDB PV Reuse   ==="
echo "=========================================================="

echo "[CLEANUP] Deleting Deployment '$NAMESPACE/mariadb'..."
kubectl delete deployment mariadb -n "$NAMESPACE" --ignore-not-found=true --timeout=60s 2>/dev/null || true

echo "[CLEANUP] Deleting PVC '$NAMESPACE/mariadb'..."
kubectl delete pvc mariadb -n "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true

echo "[CLEANUP] Deleting namespace '$NAMESPACE'..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s 2>/dev/null || true

echo "[CLEANUP] Deleting PersistentVolume '$PV_NAME'..."
kubectl delete pv "$PV_NAME" --ignore-not-found=true --timeout=30s 2>/dev/null || true

echo "[CLEANUP] Removing host directory '$DATA_DIR'..."
rm -rf "$DATA_DIR" 2>/dev/null || true

echo "[CLEANUP] Removing deployment manifest '$DEPLOY_FILE'..."
rm -f "$DEPLOY_FILE" 2>/dev/null || true

echo "=========================================================="
echo "=== [CLEANUP] Completed. Playground is clean.          ==="
echo "=========================================================="


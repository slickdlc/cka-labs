#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="/argo-helm.yaml"

echo "=========================================================="
echo "=== Reproducible Lifecycle Test: CKA 2025 Q-2 (q004)   ==="
echo "=========================================================="

echo "[TEST 1] Running setup.sh to initialize environment..."
bash "$SCRIPT_DIR/setup.sh"

echo "[TEST 2] Verifying validate.sh fails before student solution is applied..."
if bash "$SCRIPT_DIR/validate.sh"; then
  echo "ERROR: validate.sh unexpectedly passed on initial unconfigured state!"
  exit 1
else
  echo "[TEST 2 PASS] validate.sh correctly detected incomplete state."
fi

echo "[TEST 3] Applying official solution..."
# Step 1: Add Helm repo and update
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

# Step 2: Render Helm template to /argo-helm.yaml
helm template argocd argo/argo-cd \
  --version 7.7.3 \
  --namespace argocd \
  --set crds.install=false > "$TEMPLATE_FILE"

# Step 3: Install Helm release
helm install argocd argo/argo-cd \
  --version 7.7.3 \
  --namespace argocd \
  --set crds.install=false

echo "[TEST 4] Verifying validate.sh passes after official solution is applied..."
bash "$SCRIPT_DIR/validate.sh"

echo "[TEST 5] Running cleanup.sh to restore cluster cleanliness..."
bash "$SCRIPT_DIR/cleanup.sh"

echo "=========================================================="
echo "=== Lifecycle Test Completed Successfully! (All PASS)  ==="
echo "=========================================================="

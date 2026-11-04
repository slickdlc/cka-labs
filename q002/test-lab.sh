#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_SYSTEM="kube-system"

echo "=========================================================="
echo "=== Reproducible Lifecycle Test: CoreDNS Lab          ==="
echo "=========================================================="

echo "[TEST 1] Running setup.sh to inject faults..."
bash "$SCRIPT_DIR/setup.sh"

echo "[TEST 2] Verifying validate.sh detects initial faults (must fail)..."
if bash "$SCRIPT_DIR/validate.sh"; then
  echo "ERROR: validate.sh passed when faults were supposed to be active."
  exit 1
else
  echo "[TEST 2 PASS] validate.sh correctly detected the active faults."
fi

echo "[TEST 3] Applying automated solution..."
# 1. Fix ConfigMap
CURRENT_COREFILE=$(kubectl get configmap coredns -n "$KUBE_SYSTEM" -o jsonpath='{.data.Corefile}')
FIXED_COREFILE=$(echo "$CURRENT_COREFILE" | sed 's/forwarders \./forward \./g; s/kubernetess/kubernetes/g')
kubectl create configmap coredns -n "$KUBE_SYSTEM" \
  --from-literal=Corefile="$FIXED_COREFILE" \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Fix Service selector
kubectl patch service kube-dns -n "$KUBE_SYSTEM" -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'

# 3. Restart CoreDNS
kubectl rollout restart deployment coredns -n "$KUBE_SYSTEM"
kubectl rollout status deployment coredns -n "$KUBE_SYSTEM" --timeout=60s

# Wait briefly for endpoints and proxy sync
sleep 5

echo "[TEST 4] Running validate.sh after solution (must pass with exit 0)..."
bash "$SCRIPT_DIR/validate.sh"

echo "[TEST 5] Running cleanup.sh..."
bash "$SCRIPT_DIR/cleanup.sh"

echo "=========================================================="
echo "=== Lab successfully verified and 100% reproducible!   ==="
echo "=========================================================="

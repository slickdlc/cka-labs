#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${HOME:-/root}"
DEPLOY_FILE="$DEPLOY_DIR/mariadb-deploy.yaml"

echo "=========================================================="
echo "=== Reproducible Lifecycle Test: CKA 2025 Q-1 (q003)   ==="
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
# 1. Inspect cluster default storage class if present
DEFAULT_SC=$(kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")

SC_FIELD=""
if [ -n "$DEFAULT_SC" ]; then
  SC_FIELD="storageClassName: \"$DEFAULT_SC\""
fi

# 2. Create PVC named mariadb in namespace mariadb
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
  ${SC_FIELD}
EOF

# Wait briefly for PVC to bind
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/mariadb -n mariadb --timeout=30s

# 3. Patch ~/mariadb-deploy.yaml to replace emptyDir with persistentVolumeClaim
python3 -c "
with open('$DEPLOY_FILE', 'r') as f:
    content = f.read()
updated = content.replace('emptyDir: {}', 'persistentVolumeClaim:\n          claimName: mariadb')
with open('$DEPLOY_FILE', 'w') as f:
    f.write(updated)
" 2>/dev/null || sed -i 's/emptyDir: {}/persistentVolumeClaim:\n          claimName: mariadb/' "$DEPLOY_FILE"

# 4. Apply updated deployment
kubectl apply -f "$DEPLOY_FILE"

# 5. Wait for deployment rollout to finish
kubectl rollout status deployment mariadb -n mariadb --timeout=90s

echo "[TEST 4] Running validate.sh after solution (must exit 0)..."
bash "$SCRIPT_DIR/validate.sh"

echo "[TEST 5] Running cleanup.sh..."
bash "$SCRIPT_DIR/cleanup.sh"

echo "=========================================================="
echo "=== Lab lifecycle test passed and 100% verified!       ==="
echo "=========================================================="


#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Verifying Lab: NetworkPolicy ==="
echo "[1/4] Running setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[2/4] Applying official solution..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
EOF

echo "[3/4] Running validate.sh..."
bash "$SCRIPT_DIR/validate.sh"

echo "[4/4] Running cleanup.sh..."
bash "$SCRIPT_DIR/cleanup.sh"

echo "=== Lab validation completed successfully ==="

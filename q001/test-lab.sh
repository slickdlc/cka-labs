#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="ecommerce-prod"

echo "====================================================================="
echo "=== Reproducible Lifecycle Test: Cascading Troubleshooting Lab    ==="
echo "====================================================================="

echo "[TEST 1] Running setup.sh to inject faults..."
bash "$SCRIPT_DIR/setup.sh"

echo "[TEST 2] Verifying validate.sh correctly flags initial faults (must fail)..."
if bash "$SCRIPT_DIR/validate.sh"; then
  echo "ERROR: validate.sh unexpectedly passed when environment was faulted."
  exit 1
else
  echo "[TEST 2 PASS] validate.sh correctly identified faults."
fi

echo "[TEST 3] Applying automated solution..."

# 1. Fix Deployment order-service:
# - Remove nodeSelector
# - Fix initContainer endpoint
# - Fix Secret key reference to db_password
# - Fix readinessProbe to port 80 and path /
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: ${NAMESPACE}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-backend
  template:
    metadata:
      labels:
        app: order-backend
    spec:
      initContainers:
      - name: init-db-check
        image: busybox:1.36
        command: ["sh", "-c", "nc -z -w 2 order-db-svc.ecommerce-prod.svc.cluster.local 5432"]
      containers:
      - name: order-app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
          name: http
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: db_password
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 3
EOF

# 2. Fix Service order-service selector and targetPort
kubectl patch svc order-service -n "${NAMESPACE}" -p '{"spec":{"selector":{"app":"order-backend"},"ports":[{"name":"http","port":80,"targetPort":80,"protocol":"TCP"}]}}'

# 3. Fix NetworkPolicy order-netpol: Ingress from client-frontend and Egress to DNS/DB
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-netpol
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: order-backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: client-frontend
      ports:
      - protocol: TCP
        port: 80
  egress:
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  - to:
    - podSelector:
        matchLabels:
          app: order-db
      ports:
      - protocol: TCP
        port: 5432
EOF

# Wait for rollout and readiness
echo "[TEST 3] Waiting for deployment rollout to stabilize..."
kubectl rollout status deployment order-service -n "${NAMESPACE}" --timeout=90s
kubectl wait --namespace="${NAMESPACE}" --for=condition=Ready pod -l app=order-backend --timeout=60s

# Brief pause for endpoint and iptables propagation
sleep 4

echo "[TEST 4] Running validate.sh on fixed environment (must pass with exit 0)..."
bash "$SCRIPT_DIR/validate.sh"

echo "[TEST 5] Running cleanup.sh..."
bash "$SCRIPT_DIR/cleanup.sh"

echo "====================================================================="
echo "=== Lab successfully verified and 100% reproducible!              ==="
echo "====================================================================="

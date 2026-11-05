#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="default"
DEPLOY_NAME="wordpress"

echo "=========================================================="
echo "=== [SETUP] Initializing CKA Lab: WordPress Sidecar   ==="
echo "=========================================================="

echo "[SETUP] Cleaning up previous resources if any..."
kubectl delete deployment "$DEPLOY_NAME" -n "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true

# Wait until old pods are gone
kubectl wait --for=delete pod -l app=wordpress -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

echo "[SETUP] Creating base single-container wordpress deployment..."
cat << 'EOF' | kubectl apply -n "$NAMESPACE" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: default
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: busybox:stable
        command:
        - /bin/sh
        - -c
        - |
          mkdir -p /var/log
          touch /var/log/wordpress.log
          COUNTER=1
          while true; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [NOTICE] WordPress event #$COUNTER: GET /wp-admin 200 OK" >> /var/log/wordpress.log
            COUNTER=$((COUNTER + 1))
            sleep 3
          done
EOF

echo "[SETUP] Waiting for base deployment to become available..."
kubectl rollout status deployment/"$DEPLOY_NAME" -n "$NAMESPACE" --timeout=60s

echo "=========================================================="
echo "=== [SETUP COMPLETED] Initial lab state is active.     ==="
echo "=========================================================="

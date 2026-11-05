#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="default"
DEPLOY_NAME="wordpress"

echo "=========================================================="
echo "=== [SETUP] Initializing CKA Lab: WordPress Resources  ==="
echo "=========================================================="

echo "[SETUP] Cleaning up previous resources if any..."
kubectl delete deployment "$DEPLOY_NAME" -n "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true

# Wait until old pods are gone
kubectl wait --for=delete pod -l app=wordpress -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

echo "[SETUP] Creating wordpress deployment with misconfigured excessive resources..."
cat << 'EOF' | kubectl apply -n "$NAMESPACE" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: default
  labels:
    app: wordpress
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      initContainers:
      - name: init-wordpress
        image: busybox:stable
        command:
        - /bin/sh
        - -c
        - 'echo "Init: verifying database connectivity..."; sleep 2'
        resources:
          requests:
            cpu: "16"
            memory: "64Gi"
          limits:
            cpu: "16"
            memory: "64Gi"
      containers:
      - name: wordpress
        image: busybox:stable
        command:
        - /bin/sh
        - -c
        - 'while true; do echo "WordPress service running on port 80..."; sleep 10; done'
        resources:
          requests:
            cpu: "16"
            memory: "64Gi"
          limits:
            cpu: "16"
            memory: "64Gi"
EOF

echo "[SETUP] Deployment '$DEPLOY_NAME' created."
echo "[SETUP] Pods are currently pending due to excessive resource requests."
echo "=========================================================="
echo "=== [SETUP COMPLETED] Initial lab state is active.     ==="
echo "=========================================================="


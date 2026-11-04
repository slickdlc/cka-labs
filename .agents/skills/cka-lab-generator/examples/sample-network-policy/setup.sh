#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="ecommerce"
OTHER_NS="analytics"

echo "[SETUP] Setting up environment for CKA lab: Backend NetworkPolicy..."

# Pre-cleanup for idempotence
kubectl delete namespace "$NAMESPACE" "$OTHER_NS" --ignore-not-found=true --timeout=30s 2>/dev/null || true

# Create namespaces
kubectl create namespace "$NAMESPACE"
kubectl create namespace "$OTHER_NS"

# Deploy backend (simulated with python http server on 8080)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: backend-app
  namespace: ${NAMESPACE}
  labels:
    app: backend
spec:
  containers:
  - name: server
    image: python:3.9-alpine
    command: ["python", "-m", "http.server", "8080"]
    ports:
    - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: backend
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend-app
  namespace: ${NAMESPACE}
  labels:
    app: frontend
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: rogue-client
  namespace: ${NAMESPACE}
  labels:
    app: rogue
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: external-client
  namespace: ${OTHER_NS}
  labels:
    app: external
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

echo "[SETUP] Waiting for pods to reach Ready status..."
kubectl wait --namespace="$NAMESPACE" --for=condition=Ready pod/backend-app --timeout=60s
kubectl wait --namespace="$NAMESPACE" --for=condition=Ready pod/frontend-app --timeout=60s
kubectl wait --namespace="$NAMESPACE" --for=condition=Ready pod/rogue-client --timeout=60s
kubectl wait --namespace="$OTHER_NS" --for=condition=Ready pod/external-client --timeout=60s

echo "[SETUP] Environment ready. You may begin the task in namespace '$NAMESPACE'."

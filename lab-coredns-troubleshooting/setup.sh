#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="analytics"
KUBE_SYSTEM="kube-system"
BACKUP_DIR="/tmp/cka-coredns-backup"

echo "[SETUP] Starting CoreDNS troubleshooting scenario injection..."

# 1. Create temporary backup directory if it does not exist
mkdir -p "$BACKUP_DIR"

# 2. Back up original state only if previous backups do not exist
if [ ! -f "$BACKUP_DIR/coredns-cm.yaml" ]; then
  echo "[SETUP] Backing up ConfigMap 'coredns'..."
  kubectl get configmap coredns -n "$KUBE_SYSTEM" -o yaml > "$BACKUP_DIR/coredns-cm.yaml"
fi

if [ ! -f "$BACKUP_DIR/kube-dns-svc.yaml" ]; then
  echo "[SETUP] Backing up Service 'kube-dns'..."
  kubectl get service kube-dns -n "$KUBE_SYSTEM" -o yaml > "$BACKUP_DIR/kube-dns-svc.yaml"
fi

# 3. Prepare test namespace 'analytics' and workloads
echo "[SETUP] Preparing namespace '$NAMESPACE' and test workloads..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true
kubectl create namespace "$NAMESPACE"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: database-backend
  namespace: ${NAMESPACE}
  labels:
    app: database
spec:
  containers:
  - name: db
    image: nginx:1.25-alpine
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: database-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: database
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: data-processor
  namespace: ${NAMESPACE}
  labels:
    app: processor
spec:
  containers:
  - name: processor
    image: busybox:1.28
    command: ["sh", "-c", "while true; do sleep 3600; done"]
EOF

echo "[SETUP] Waiting for test workloads to reach Ready status..."
kubectl wait --namespace="$NAMESPACE" --for=condition=Ready pod/database-backend --timeout=60s
kubectl wait --namespace="$NAMESPACE" --for=condition=Ready pod/data-processor --timeout=60s

# 4. Inject Fault 1: Syntax error / unknown directive in ConfigMap 'coredns'
echo "[SETUP] Injecting Fault 1: Corrupting Corefile in ConfigMap 'coredns'..."
CURRENT_COREFILE=$(kubectl get configmap coredns -n "$KUBE_SYSTEM" -o jsonpath='{.data.Corefile}')

if echo "$CURRENT_COREFILE" | grep -q "forward \."; then
  MODIFIED_COREFILE=$(echo "$CURRENT_COREFILE" | sed 's/forward \./forwarders \./g')
elif echo "$CURRENT_COREFILE" | grep -q "kubernetes"; then
  MODIFIED_COREFILE=$(echo "$CURRENT_COREFILE" | sed 's/kubernetes/kubernetess/g')
else
  MODIFIED_COREFILE="invalid_directive_coredns
$CURRENT_COREFILE"
fi

kubectl create configmap coredns -n "$KUBE_SYSTEM" \
  --from-literal=Corefile="$MODIFIED_COREFILE" \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Inject Fault 2: Mismatched selector in Service 'kube-dns'
echo "[SETUP] Injecting Fault 2: Breaking selector in Service 'kube-dns'..."
kubectl patch service kube-dns -n "$KUBE_SYSTEM" -p '{"spec":{"selector":{"k8s-app":"coredns-invalid-selector"}}}'

# 6. Restart coredns deployment to trigger failure state
echo "[SETUP] Restarting Deployment coredns in '$KUBE_SYSTEM'..."
kubectl rollout restart deployment coredns -n "$KUBE_SYSTEM"

echo "[SETUP] Waiting for failure state to propagate..."
sleep 8

echo "[SETUP] Scenario successfully injected."
echo "[SETUP] Inspect pods in '$KUBE_SYSTEM' and endpoints for 'kube-dns'. Good luck!"

#!/usr/bin/env bash
set -euo pipefail

KUBE_SYSTEM="kube-system"
APP_NS="analytics"
BACKUP_DIR="/tmp/cka-coredns-backup"

echo "[CLEANUP] Restoring cluster to clean state..."

# 1. Delete test namespace
kubectl delete namespace "$APP_NS" --ignore-not-found=true --timeout=60s 2>/dev/null || true

# 2. Restore ConfigMap and Service if backups exist
if [ -f "$BACKUP_DIR/coredns-cm.yaml" ]; then
  echo "[CLEANUP] Restoring ConfigMap 'coredns' from backup..."
  kubectl apply -f "$BACKUP_DIR/coredns-cm.yaml"
else
  echo "[CLEANUP] Backup not found. Re-creating clean Corefile in ConfigMap..."
  CURRENT_COREFILE=$(kubectl get configmap coredns -n "$KUBE_SYSTEM" -o jsonpath='{.data.Corefile}' 2>/dev/null || echo "")
  CLEAN_COREFILE=$(echo "$CURRENT_COREFILE" | sed 's/forwarders \./forward \./g; s/kubernetess/kubernetes/g')
  kubectl create configmap coredns -n "$KUBE_SYSTEM" \
    --from-literal=Corefile="$CLEAN_COREFILE" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

if [ -f "$BACKUP_DIR/kube-dns-svc.yaml" ]; then
  echo "[CLEANUP] Restoring Service 'kube-dns' from backup..."
  kubectl apply -f "$BACKUP_DIR/kube-dns-svc.yaml"
else
  echo "[CLEANUP] Resetting selector for Service 'kube-dns'..."
  kubectl patch service kube-dns -n "$KUBE_SYSTEM" -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'
fi

# 3. Restart deployment and wait for rollout
echo "[CLEANUP] Restarting deployment coredns..."
kubectl rollout restart deployment coredns -n "$KUBE_SYSTEM"
kubectl rollout status deployment coredns -n "$KUBE_SYSTEM" --timeout=60s

# 4. Remove backup directory
rm -rf "$BACKUP_DIR"

echo "[CLEANUP] Complete. Cluster returned to standard operational state."

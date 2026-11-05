#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mariadb"
PV_NAME="mariadb-pv"
DEPLOY_DIR="${HOME:-/root}"
DEPLOY_FILE="$DEPLOY_DIR/mariadb-deploy.yaml"
DATA_DIR="/data/mariadb"

echo "=========================================================="
echo "=== [SETUP] Initializing CKA Lab: MariaDB PV Reuse     ==="
echo "=========================================================="

# 1. Clean up existing resources from previous runs
echo "[SETUP] Cleaning up previous lab state if present..."
kubectl delete deployment mariadb -n "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true
kubectl delete pvc mariadb -n "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true
kubectl delete pv "$PV_NAME" --ignore-not-found=true --timeout=30s 2>/dev/null || true
rm -f "$DEPLOY_FILE"

# 2. Prepare host storage directory and retained canary data
echo "[SETUP] Setting up persistent storage path at '$DATA_DIR'..."
mkdir -p "$DATA_DIR"
chmod 777 "$DATA_DIR"
cat << 'EOF' > "$DATA_DIR/retained_data_marker.txt"
MARIADB_PRESERVED_DATA_BLOCK
STATUS: VALID
CREATED_BY: CKA_SIMULATOR_BACKUP
EOF
chmod 666 "$DATA_DIR/retained_data_marker.txt"

# 3. Detect default StorageClass if one exists in the playground cluster
DEFAULT_SC=$(kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")

SC_CONFIG=""
if [ -n "$DEFAULT_SC" ]; then
  echo "[SETUP] Detected default StorageClass '$DEFAULT_SC'. Configuring PV to match..."
  SC_CONFIG="storageClassName: \"$DEFAULT_SC\""
else
  echo "[SETUP] No default StorageClass detected. Using standard empty/manual storageClass..."
  SC_CONFIG="storageClassName: \"\""
fi

# 4. Create target namespace
echo "[SETUP] Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE"

# 5. Create the retained PersistentVolume (Available state)
echo "[SETUP] Creating PersistentVolume '$PV_NAME'..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
  labels:
    app: mariadb
    type: local
spec:
  capacity:
    storage: 250Mi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  ${SC_CONFIG}
  hostPath:
    path: ${DATA_DIR}
    type: DirectoryOrCreate
EOF

# 6. Verify PersistentVolume is in Available state
echo "[SETUP] Verifying PersistentVolume status..."
PV_STATUS=$(kubectl get pv "$PV_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
echo "[SETUP] PV '$PV_NAME' phase: $PV_STATUS"

# 7. Create ~/mariadb-deploy.yaml with temporary emptyDir volume
echo "[SETUP] Creating initial deployment manifest at '$DEPLOY_FILE'..."
cat << 'EOF' > "$DEPLOY_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mariadb
  labels:
    app: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.11
        env:
        - name: MARIADB_ROOT_PASSWORD
          value: "secret123"
        - name: MYSQL_ROOT_PASSWORD
          value: "secret123"
        ports:
        - containerPort: 3306
          name: mariadb
        volumeMounts:
        - name: mariadb-data
          mountPath: /var/lib/mysql
      volumes:
      - name: mariadb-data
        emptyDir: {}
EOF
chmod 644 "$DEPLOY_FILE"

# 8. Best-effort image pre-pulling to reduce student waiting time
echo "[SETUP] Pre-caching container image (best-effort)..."
crictl pull mariadb:10.11 2>/dev/null || docker pull mariadb:10.11 2>/dev/null || true

echo "=========================================================="
echo "=== [SETUP] Lab initialization completed successfully! ==="
echo "=== File created: $DEPLOY_FILE                         ==="
echo "=========================================================="


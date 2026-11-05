#!/usr/bin/env bash
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="mariadb"
PVC_NAME="mariadb"
DEPLOY_NAME="mariadb"
PV_NAME="mariadb-pv"
DEPLOY_DIR="${HOME:-/root}"
DEPLOY_FILE="$DEPLOY_DIR/mariadb-deploy.yaml"

TOTAL=0
PASSED=0
FAILED=0

pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  ((PASSED++))
  ((TOTAL++))
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  if [ -n "${2:-}" ]; then
    echo -e "       ${YELLOW}Detail:${NC} $2"
  fi
  ((FAILED++))
  ((TOTAL++))
}

echo "=========================================================="
echo "=== Validating Lab: MariaDB Persistent Volume Reuse    ==="
echo "=========================================================="

# ---------------------------------------------------------
# Check 1: Existence of PersistentVolumeClaim in namespace 'mariadb'
# ---------------------------------------------------------
PVC_JSON=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json 2>/dev/null || echo "")
if [ -n "$PVC_JSON" ]; then
  pass "PersistentVolumeClaim '$PVC_NAME' exists in namespace '$NAMESPACE'"
else
  fail "PersistentVolumeClaim '$PVC_NAME' not found in namespace '$NAMESPACE'" "Run: kubectl get pvc -n $NAMESPACE"
fi

# ---------------------------------------------------------
# Check 2: PVC Spec Access Modes
# ---------------------------------------------------------
PVC_ACCESS_MODES=$(echo "$PVC_JSON" | jq -r '.spec.accessModes[]?' 2>/dev/null || kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.accessModes[*]}' 2>/dev/null || echo "")
if echo "$PVC_ACCESS_MODES" | grep -qw "ReadWriteOnce"; then
  pass "PVC accessMode includes 'ReadWriteOnce'"
else
  fail "PVC accessMode does not match 'ReadWriteOnce'" "Actual: ${PVC_ACCESS_MODES:-None}, Expected: ReadWriteOnce"
fi

# ---------------------------------------------------------
# Check 3: PVC Spec Storage Request
# ---------------------------------------------------------
PVC_STORAGE_REQ=$(echo "$PVC_JSON" | jq -r '.spec.resources.requests.storage // empty' 2>/dev/null || kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo "")
if [ "$PVC_STORAGE_REQ" = "250Mi" ]; then
  pass "PVC requests exactly '250Mi' of storage"
else
  fail "PVC storage request does not equal '250Mi'" "Actual: ${PVC_STORAGE_REQ:-None}, Expected: 250Mi"
fi

# ---------------------------------------------------------
# Check 4: PVC Binding Status
# ---------------------------------------------------------
PVC_PHASE=$(echo "$PVC_JSON" | jq -r '.status.phase // empty' 2>/dev/null || kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
BOUND_PV=$(echo "$PVC_JSON" | jq -r '.spec.volumeName // empty' 2>/dev/null || kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")

if [ "$PVC_PHASE" = "Bound" ]; then
  pass "PVC '$PVC_NAME' is successfully 'Bound' to PV '${BOUND_PV:-mariadb-pv}'"
else
  fail "PVC '$PVC_NAME' is not in 'Bound' phase" "Phase: ${PVC_PHASE:-Unknown}. Check: kubectl describe pvc $PVC_NAME -n $NAMESPACE"
fi

# ---------------------------------------------------------
# Check 5: Deployment Manifest File (~/mariadb-deploy.yaml)
# ---------------------------------------------------------
if [ -f "$DEPLOY_FILE" ]; then
  if grep -q "persistentVolumeClaim" "$DEPLOY_FILE" && grep -q "claimName:\s*mariadb" "$DEPLOY_FILE"; then
    pass "Deployment file '$DEPLOY_FILE' was updated with persistentVolumeClaim 'mariadb'"
  elif grep -q "emptyDir" "$DEPLOY_FILE"; then
    fail "Deployment file '$DEPLOY_FILE' still specifies emptyDir" "Replace 'emptyDir: {}' with persistentVolumeClaim configuration"
  else
    fail "Deployment file '$DEPLOY_FILE' does not correctly configure persistentVolumeClaim 'mariadb'"
  fi
else
  fail "Deployment manifest '$DEPLOY_FILE' not found"
fi

# ---------------------------------------------------------
# Check 6: Deployment Existence in Namespace
# ---------------------------------------------------------
DEPLOY_JSON=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o json 2>/dev/null || echo "")
if [ -n "$DEPLOY_JSON" ]; then
  pass "Deployment '$DEPLOY_NAME' exists in namespace '$NAMESPACE'"
else
  fail "Deployment '$DEPLOY_NAME' not found in namespace '$NAMESPACE'" "Apply with: kubectl apply -f $DEPLOY_FILE"
fi

# ---------------------------------------------------------
# Check 7: Deployment Pod Spec Volume Mounts & PVC Binding
# ---------------------------------------------------------
CONFIGURED_CLAIM=$(echo "$DEPLOY_JSON" | jq -r '.spec.template.spec.volumes[]? | select(.persistentVolumeClaim != null) | .persistentVolumeClaim.claimName' 2>/dev/null || kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null || echo "")

if [ "$CONFIGURED_CLAIM" = "$PVC_NAME" ]; then
  pass "Deployment pod template references PVC claimName '$PVC_NAME'"
else
  fail "Deployment pod template does not reference PVC '$PVC_NAME'" "Actual claimName: '${CONFIGURED_CLAIM:-None}'"
fi

MOUNT_PATH=$(echo "$DEPLOY_JSON" | jq -r '.spec.template.spec.containers[]?.volumeMounts[]? | select(.mountPath == "/var/lib/mysql") | .mountPath' 2>/dev/null || kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].volumeMounts[?(@.mountPath=="/var/lib/mysql")].mountPath}' 2>/dev/null || echo "")

if [ "$MOUNT_PATH" = "/var/lib/mysql" ]; then
  pass "Deployment container mounts volume at '/var/lib/mysql'"
else
  fail "Deployment container missing mountPath '/var/lib/mysql'"
fi

# ---------------------------------------------------------
# Check 8: Deployment Replicas & Readiness
# ---------------------------------------------------------
AVAILABLE_REPLICAS=$(echo "$DEPLOY_JSON" | jq -r '.status.availableReplicas // 0' 2>/dev/null || kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
DESIRED_REPLICAS=$(echo "$DEPLOY_JSON" | jq -r '.spec.replicas // 1' 2>/dev/null || kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

if [ -n "$AVAILABLE_REPLICAS" ] && [ "$AVAILABLE_REPLICAS" -ge 1 ] && [ "$AVAILABLE_REPLICAS" -eq "$DESIRED_REPLICAS" ]; then
  pass "Deployment has all replicas available ($AVAILABLE_REPLICAS/$DESIRED_REPLICAS)"
else
  fail "Deployment does not have desired replicas available" "Available: ${AVAILABLE_REPLICAS:-0}, Desired: $DESIRED_REPLICAS"
fi

# ---------------------------------------------------------
# Check 9: Pod Running State and Ready condition
# ---------------------------------------------------------
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=mariadb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD_NAME" ]; then
  POD_PHASE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  POD_READY=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
  
  if [ "$POD_PHASE" = "Running" ] && [ "$POD_READY" = "true" ]; then
    pass "Pod '$POD_NAME' is Running and Ready (1/1)"
  else
    fail "Pod '$POD_NAME' is not healthy" "Phase: $POD_PHASE, Ready: $POD_READY"
  fi
else
  fail "No pods found for Deployment '$DEPLOY_NAME' in namespace '$NAMESPACE'"
fi

# ---------------------------------------------------------
# Check 10: Functional Data Preservation & Persistence Check
# ---------------------------------------------------------
if [ -n "$POD_NAME" ]; then
  DATA_CHECK=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /var/lib/mysql/retained_data_marker.txt 2>/dev/null || echo "")
  if echo "$DATA_CHECK" | grep -q "MARIADB_PRESERVED_DATA_BLOCK"; then
    pass "Functional test passed: Original retained volume data is accessible inside container mount"
  else
    fail "Functional test failed: Retained data file '/var/lib/mysql/retained_data_marker.txt' is missing from pod" "Check volume mounting"
  fi
fi

# ---------------------------------------------------------
# Final Score Summary
# ---------------------------------------------------------
echo "=========================================================="
echo -e "Total Checks: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}SUCCESS! All requirements for CKA 2025 Q-1 satisfied.${NC}"
  exit 0
else
  echo -e "${RED}FAILURE! One or more requirements failed. Check the details above.${NC}"
  exit 1
fi


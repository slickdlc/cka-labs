#!/usr/bin/env bash
set -uo pipefail

NAMESPACE="default"
DEPLOY_NAME="wordpress"
SIDECAR_NAME="sidecar"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED_COUNT=0
FAILED_COUNT=0

log_pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  PASSED_COUNT=$((PASSED_COUNT + 1))
}

log_fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  FAILED_COUNT=$((FAILED_COUNT + 1))
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

echo "=========================================================="
echo "=== [VALIDATION] Evaluating CKA Lab: WordPress Sidecar ==="
echo "=========================================================="

# 1. Check Deployment exists
log_info "1. Validating Deployment '$DEPLOY_NAME' existence..."
if kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" &>/dev/null; then
  log_pass "Deployment '$DEPLOY_NAME' exists in namespace '$NAMESPACE'."
else
  log_fail "Deployment '$DEPLOY_NAME' was not found in namespace '$NAMESPACE'."
  echo -e "\n${RED}=== RESULT: FAILED ($PASSED_COUNT passed, $FAILED_COUNT failed) ===${NC}"
  exit 1
fi

# 2. Check rollout status
log_info "2. Validating Deployment rollout and readiness..."
REPLICAS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
READY_REPLICAS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

if [ "$REPLICAS" -gt 0 ] && [ "$REPLICAS" = "$READY_REPLICAS" ]; then
  log_pass "All replicas ($READY_REPLICAS/$REPLICAS) are Ready."
else
  log_fail "Replicas not fully ready. Expected: $REPLICAS, Ready: $READY_REPLICAS"
fi

# 3. Get Pod details
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$POD_NAME" ]; then
  log_fail "No running Pod found for deployment '$DEPLOY_NAME' (selector app=wordpress)."
  echo -e "\n${RED}=== RESULT: FAILED ($PASSED_COUNT passed, $FAILED_COUNT failed) ===${NC}"
  exit 1
fi

# Check container count in the pod
CONTAINER_NAMES=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')
CONTAINER_COUNT=$(echo "$CONTAINER_NAMES" | wc -w)
log_info "3. Checking container count in Pod '$POD_NAME' (found: $CONTAINER_COUNT)..."
if [ "$CONTAINER_COUNT" -ge 2 ]; then
  log_pass "Pod has at least 2 containers ($CONTAINER_NAMES)."
else
  log_fail "Pod expected to have at least 2 containers, but found $CONTAINER_COUNT ($CONTAINER_NAMES)."
fi

# 4. Check sidecar container presence, image, and command
log_info "4. Checking sidecar container specification..."
SIDECAR_IMAGE=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="'$SIDECAR_NAME'")].image}' 2>/dev/null || echo "")

if [ -n "$SIDECAR_IMAGE" ]; then
  log_pass "Container '$SIDECAR_NAME' exists in deployment template."
  if [ "$SIDECAR_IMAGE" = "busybox:stable" ]; then
    log_pass "Sidecar image is exactly 'busybox:stable'."
  else
    log_fail "Sidecar image mismatch: expected 'busybox:stable', got '$SIDECAR_IMAGE'."
  fi
else
  log_fail "Container named '$SIDECAR_NAME' was not found in deployment template."
fi

# Check command in sidecar
SIDECAR_CMD=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="'$SIDECAR_NAME'")].command}' 2>/dev/null || echo "")
SIDECAR_ARGS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="'$SIDECAR_NAME'")].args}' 2>/dev/null || echo "")
FULL_CMD="$SIDECAR_CMD $SIDECAR_ARGS"

if echo "$FULL_CMD" | grep -q "tail -f /var/log/wordpress.log" && echo "$FULL_CMD" | grep -q "/bin/sh"; then
  log_pass "Sidecar container executes '/bin/sh -c tail -f /var/log/wordpress.log'."
else
  log_fail "Sidecar command mismatch. Expected '/bin/sh -c tail -f /var/log/wordpress.log', found command='$SIDECAR_CMD', args='$SIDECAR_ARGS'."
fi

# 5. Check volume mount at /var/log on both containers
log_info "5. Checking volume mount at /var/log on co-located containers..."
SIDECAR_MOUNT=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="'$SIDECAR_NAME'")].volumeMounts[?(@.mountPath=="/var/log")].name}' 2>/dev/null || echo "")
MAIN_MOUNT=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name!="'$SIDECAR_NAME'")].volumeMounts[?(@.mountPath=="/var/log")].name}' 2>/dev/null || echo "")

if [ -n "$SIDECAR_MOUNT" ]; then
  log_pass "Container '$SIDECAR_NAME' has a volume mounted at '/var/log' (volume name: '$SIDECAR_MOUNT')."
else
  log_fail "Container '$SIDECAR_NAME' does not mount any volume at '/var/log'."
fi

if [ -n "$MAIN_MOUNT" ]; then
  log_pass "Main container has a volume mounted at '/var/log' (volume name: '$MAIN_MOUNT')."
else
  log_fail "Main container does not mount any volume at '/var/log'."
fi

if [ -n "$SIDECAR_MOUNT" ] && [ "$SIDECAR_MOUNT" = "$MAIN_MOUNT" ]; then
  log_pass "Both containers share the exact same volume ('$SIDECAR_MOUNT')."
else
  log_fail "Volume mismatch: sidecar uses '$SIDECAR_MOUNT' while main uses '$MAIN_MOUNT'."
fi

# 6. Functional Check: Streamed logs from sidecar
log_info "6. Performing functional log streaming verification..."
sleep 3
SIDECAR_LOGS=$(kubectl logs deployment/"$DEPLOY_NAME" -c "$SIDECAR_NAME" --tail=20 2>/dev/null || echo "")

if [ -n "$SIDECAR_LOGS" ] && echo "$SIDECAR_LOGS" | grep -q -i "WordPress"; then
  log_pass "Sidecar container successfully streams logs from shared '/var/log/wordpress.log'."
  echo -e "     ${YELLOW}Sample log output:${NC}"
  echo "$SIDECAR_LOGS" | tail -n 2 | sed 's/^/       /'
else
  log_fail "Sidecar container logs did not stream expected log entries. Actual output: '$SIDECAR_LOGS'"
fi

# Summary
echo "=========================================================="
if [ "$FAILED_COUNT" -eq 0 ]; then
  echo -e "${GREEN}=== RESULT: ALL CHECKS PASSED ($PASSED_COUNT passed, 0 failed) ===${NC}"
  exit 0
else
  echo -e "${RED}=== RESULT: FAILED ($PASSED_COUNT passed, $FAILED_COUNT failed) ===${NC}"
  exit 1
fi

#!/usr/bin/env bash
set -uo pipefail

NAMESPACE="default"
DEPLOY_NAME="wordpress"

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

# Helper to normalize CPU values to millicores (integer)
parse_cpu_to_m() {
  local val="$1"
  val=$(echo "$val" | tr -d ' "')
  if [[ "$val" =~ ^([0-9]+)m$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$val" =~ ^([0-9]+)$ ]]; then
    echo $(( BASH_REMATCH[1] * 1000 ))
  elif [[ "$val" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    # e.g., 0.5 -> 500m
    awk -v c="$val" 'BEGIN { printf "%.0f", c * 1000 }'
  else
    echo "0"
  fi
}

# Helper to normalize Memory values to KiB (integer)
parse_mem_to_kib() {
  local val="$1"
  val=$(echo "$val" | tr -d ' "')
  if [[ "$val" =~ ^([0-9]+)Ki$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$val" =~ ^([0-9]+)Mi$ ]]; then
    echo $(( BASH_REMATCH[1] * 1024 ))
  elif [[ "$val" =~ ^([0-9]+)Gi$ ]]; then
    echo $(( BASH_REMATCH[1] * 1024 * 1024 ))
  elif [[ "$val" =~ ^([0-9]+)Ti$ ]]; then
    echo $(( BASH_REMATCH[1] * 1024 * 1024 * 1024 ))
  elif [[ "$val" =~ ^([0-9]+)K$ ]]; then
    echo $(( (BASH_REMATCH[1] * 1000) / 1024 ))
  elif [[ "$val" =~ ^([0-9]+)M$ ]]; then
    echo $(( (BASH_REMATCH[1] * 1000 * 1000) / 1024 ))
  elif [[ "$val" =~ ^([0-9]+)G$ ]]; then
    echo $(( (BASH_REMATCH[1] * 1000 * 1000 * 1000) / 1024 ))
  elif [[ "$val" =~ ^([0-9]+)$ ]]; then
    echo $(( BASH_REMATCH[1] / 1024 ))
  else
    echo "0"
  fi
}

echo "=========================================================="
echo "=== [VALIDATION] Evaluating CKA Lab: WordPress Resources ==="
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

# 2. Check Replicas count is 3
log_info "2. Validating Deployment replica count..."
SPEC_REPLICAS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
if [ "$SPEC_REPLICAS" -eq 3 ]; then
  log_pass "Deployment spec.replicas is set to 3."
else
  log_fail "Deployment spec.replicas mismatch: expected 3, got '$SPEC_REPLICAS'."
fi

# 3. Check Rollout and Ready Replicas
log_info "3. Validating Deployment pod readiness (3/3 Ready)..."
READY_REPLICAS=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$READY_REPLICAS" -eq 3 ]; then
  log_pass "All 3 replicas are Running and Ready."
else
  log_fail "Pods not ready. Expected 3 ready replicas, but currently ready: '$READY_REPLICAS'."
fi

# 4. Check Container and InitContainer presence
log_info "4. Checking containers and initContainers in deployment template..."
INIT_COUNT=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{range .spec.template.spec.initContainers[*]}{.name}{" "}{end}' | wc -w)
MAIN_COUNT=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" "}{end}' | wc -w)

if [ "$INIT_COUNT" -ge 1 ]; then
  log_pass "At least one initContainer exists (count: $INIT_COUNT)."
else
  log_fail "No initContainer found in deployment template."
fi

if [ "$MAIN_COUNT" -ge 1 ]; then
  log_pass "At least one main container exists (count: $MAIN_COUNT)."
else
  log_fail "No main container found in deployment template."
fi

# 5. Extract Resources
INIT_REQ_CPU=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.initContainers[0].resources.requests.cpu}' 2>/dev/null || echo "")
INIT_REQ_MEM=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.initContainers[0].resources.requests.memory}' 2>/dev/null || echo "")
INIT_LIM_CPU=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.initContainers[0].resources.limits.cpu}' 2>/dev/null || echo "")
INIT_LIM_MEM=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.initContainers[0].resources.limits.memory}' 2>/dev/null || echo "")

MAIN_REQ_CPU=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
MAIN_REQ_MEM=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
MAIN_LIM_CPU=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
MAIN_LIM_MEM=$(kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")

log_info "5. Verifying resources are explicitly defined on both init and main containers..."
if [ -n "$INIT_REQ_CPU" ] && [ -n "$INIT_REQ_MEM" ] && [ -n "$INIT_LIM_CPU" ] && [ -n "$INIT_LIM_MEM" ]; then
  log_pass "Init container has all resource requests and limits specified (CPU req: $INIT_REQ_CPU, mem req: $INIT_REQ_MEM, CPU lim: $INIT_LIM_CPU, mem lim: $INIT_LIM_MEM)."
else
  log_fail "Init container is missing one or more resource fields (CPU req: '$INIT_REQ_CPU', mem req: '$INIT_REQ_MEM', CPU lim: '$INIT_LIM_CPU', mem lim: '$INIT_LIM_MEM')."
fi

if [ -n "$MAIN_REQ_CPU" ] && [ -n "$MAIN_REQ_MEM" ] && [ -n "$MAIN_LIM_CPU" ] && [ -n "$MAIN_LIM_MEM" ]; then
  log_pass "Main container has all resource requests and limits specified (CPU req: $MAIN_REQ_CPU, mem req: $MAIN_REQ_MEM, CPU lim: $MAIN_LIM_CPU, mem lim: $MAIN_LIM_MEM)."
else
  log_fail "Main container is missing one or more resource fields (CPU req: '$MAIN_REQ_CPU', mem req: '$MAIN_REQ_MEM', CPU lim: '$MAIN_LIM_CPU', mem lim: '$MAIN_LIM_MEM')."
fi

# 6. Verify initContainers and containers use exactly the same resource requests and limits
log_info "6. Verifying init container and main container use identical requests and limits..."
INIT_REQ_CPU_M=$(parse_cpu_to_m "$INIT_REQ_CPU")
MAIN_REQ_CPU_M=$(parse_cpu_to_m "$MAIN_REQ_CPU")
INIT_REQ_MEM_K=$(parse_mem_to_kib "$INIT_REQ_MEM")
MAIN_REQ_MEM_K=$(parse_mem_to_kib "$MAIN_REQ_MEM")

INIT_LIM_CPU_M=$(parse_cpu_to_m "$INIT_LIM_CPU")
MAIN_LIM_CPU_M=$(parse_cpu_to_m "$MAIN_LIM_CPU")
INIT_LIM_MEM_K=$(parse_mem_to_kib "$INIT_LIM_MEM")
MAIN_LIM_MEM_K=$(parse_mem_to_kib "$MAIN_LIM_MEM")

# CPU Requests equality
if [ "$INIT_REQ_CPU_M" -gt 0 ] && [ "$INIT_REQ_CPU_M" -eq "$MAIN_REQ_CPU_M" ]; then
  log_pass "CPU requests match between init and main containers ($INIT_REQ_CPU_M m)."
else
  log_fail "CPU requests do not match: init='$INIT_REQ_CPU' (${INIT_REQ_CPU_M}m) vs main='$MAIN_REQ_CPU' (${MAIN_REQ_CPU_M}m)."
fi

# Memory Requests equality
if [ "$INIT_REQ_MEM_K" -gt 0 ] && [ "$INIT_REQ_MEM_K" -eq "$MAIN_REQ_MEM_K" ]; then
  log_pass "Memory requests match between init and main containers ($INIT_REQ_MEM_K KiB)."
else
  log_fail "Memory requests do not match: init='$INIT_REQ_MEM' (${INIT_REQ_MEM_K}KiB) vs main='$MAIN_REQ_MEM' (${MAIN_REQ_MEM_K}KiB)."
fi

# CPU Limits equality
if [ "$INIT_LIM_CPU_M" -gt 0 ] && [ "$INIT_LIM_CPU_M" -eq "$MAIN_LIM_CPU_M" ]; then
  log_pass "CPU limits match between init and main containers ($INIT_LIM_CPU_M m)."
else
  log_fail "CPU limits do not match: init='$INIT_LIM_CPU' (${INIT_LIM_CPU_M}m) vs main='$MAIN_LIM_CPU' (${MAIN_LIM_CPU_M}m)."
fi

# Memory Limits equality
if [ "$INIT_LIM_MEM_K" -gt 0 ] && [ "$INIT_LIM_MEM_K" -eq "$MAIN_LIM_MEM_K" ]; then
  log_pass "Memory limits match between init and main containers ($INIT_LIM_MEM_K KiB)."
else
  log_fail "Memory limits do not match: init='$INIT_LIM_MEM' (${INIT_LIM_MEM_K}KiB) vs main='$MAIN_LIM_MEM' (${MAIN_LIM_MEM_K}KiB)."
fi

# 7. Validate Fair Sharing across 3 Pods with overhead
log_info "7. Validating fair division across 3 pods and node overhead..."
TARGET_NODE=$(kubectl get pods -n "$NAMESPACE" -l app=wordpress -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "")
if [ -z "$TARGET_NODE" ]; then
  TARGET_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -n "$TARGET_NODE" ]; then
  NODE_RAW_CPU=$(kubectl get node "$TARGET_NODE" -o jsonpath='{.status.allocatable.cpu}')
  NODE_RAW_MEM=$(kubectl get node "$TARGET_NODE" -o jsonpath='{.status.allocatable.memory}')
  NODE_CPU_M=$(parse_cpu_to_m "$NODE_RAW_CPU")
  NODE_MEM_K=$(parse_mem_to_kib "$NODE_RAW_MEM")
  
  # Total requested across 3 pods
  TOTAL_3POD_CPU_M=$(( MAIN_REQ_CPU_M * 3 ))
  TOTAL_3POD_MEM_K=$(( MAIN_REQ_MEM_K * 3 ))
  
  # Check overhead: 3 pods requests must not exceed 90% of node allocatable
  # (leaving >= 10% overhead for system daemons and avoiding node instability)
  MAX_ALLOWED_CPU=$(( (NODE_CPU_M * 90) / 100 ))
  MAX_ALLOWED_MEM=$(( (NODE_MEM_K * 90) / 100 ))
  
  if [ "$TOTAL_3POD_CPU_M" -le "$MAX_ALLOWED_CPU" ] && [ "$MAIN_REQ_CPU_M" -ge 20 ]; then
    log_pass "Total CPU requests for 3 pods (${TOTAL_3POD_CPU_M}m) are within safe allocatable limit with overhead (${MAX_ALLOWED_CPU}m of ${NODE_CPU_M}m total allocatable)."
  else
    log_fail "Total CPU requests (${TOTAL_3POD_CPU_M}m) exceed safe node allocatable overhead threshold (${MAX_ALLOWED_CPU}m) or are trivially low."
  fi
  
  if [ "$TOTAL_3POD_MEM_K" -le "$MAX_ALLOWED_MEM" ] && [ "$MAIN_REQ_MEM_K" -ge 32768 ]; then
    log_pass "Total Memory requests for 3 pods (${TOTAL_3POD_MEM_K} KiB) are within safe allocatable limit with overhead (${MAX_ALLOWED_MEM} KiB of ${NODE_MEM_K} KiB total allocatable)."
  else
    log_fail "Total Memory requests (${TOTAL_3POD_MEM_K} KiB) exceed safe node allocatable overhead threshold (${MAX_ALLOWED_MEM} KiB) or are trivially low."
  fi
else
  log_info "No node details accessible, skipping node capacity overhead comparison."
fi

# 8. Check requests <= limits
if [ "$MAIN_REQ_CPU_M" -le "$MAIN_LIM_CPU_M" ] && [ "$MAIN_REQ_MEM_K" -le "$MAIN_LIM_MEM_K" ]; then
  log_pass "Resource requests are less than or equal to resource limits."
else
  log_fail "Resource requests exceed limits (CPU: ${MAIN_REQ_CPU_M}m > ${MAIN_LIM_CPU_M}m or Mem: ${MAIN_REQ_MEM_K}KiB > ${MAIN_LIM_MEM_K}KiB)."
fi

# Summary
echo "=========================================================="
if [ "$FAILED_COUNT" -eq 0 ]; then
  echo -e "${GREEN}=== RESULT: ALL CHECKS PASSED ($PASSED_COUNT passed, 0 failed) ===${NC}"
  exit 0
else
  echo -e "${RED}=== RESULT: VALIDATION FAILED ($PASSED_COUNT passed, $FAILED_COUNT failed) ===${NC}"
  exit 1
fi


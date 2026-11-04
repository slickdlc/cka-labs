#!/usr/bin/env bash
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="ecommerce"
OTHER_NS="analytics"
POLICY_NAME="allow-frontend-to-backend"

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

echo "=== Evaluating Lab: Backend NetworkPolicy ==="

# 1. Resource existence
if kubectl get networkpolicy "$POLICY_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  pass "NetworkPolicy '$POLICY_NAME' exists in namespace '$NAMESPACE'"
else
  fail "NetworkPolicy '$POLICY_NAME' not found in '$NAMESPACE'"
  echo "Aborting validation early due to missing primary resource."
  exit 1
fi

# 2. Validate podSelector (app: backend)
TARGET_APP=$(kubectl get networkpolicy "$POLICY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.podSelector.matchLabels.app}' 2>/dev/null || echo "")
if [ "$TARGET_APP" = "backend" ]; then
  pass "Policy correctly applies to pods with label 'app: backend'"
else
  fail "Pod selector does not target 'app: backend'" "Current value: '$TARGET_APP'"
fi

# 3. Validate policyTypes (must contain Ingress)
TYPES=$(kubectl get networkpolicy "$POLICY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null || echo "")
if echo "$TYPES" | grep -q "Ingress"; then
  pass "policyTypes includes 'Ingress'"
else
  fail "policyTypes must include 'Ingress'" "Current value: '$TYPES'"
fi

# 4. Validate permitted port (8080/TCP)
PORT=$(kubectl get networkpolicy "$POLICY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ingress[0].ports[0].port}' 2>/dev/null || echo "")
if [ "$PORT" = "8080" ]; then
  pass "Ingress rule restricts to port 8080"
else
  fail "Ingress port is not 8080" "Current value: '$PORT'"
fi

# 5. Validate source podSelector (from app: frontend)
FROM_APP=$(kubectl get networkpolicy "$POLICY_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ingress[0].from[0].podSelector.matchLabels.app}' 2>/dev/null || echo "")
if [ "$FROM_APP" = "frontend" ]; then
  pass "Ingress rule allows pods with 'app: frontend'"
else
  fail "Allowed source does not target 'app: frontend'" "Current value: '$FROM_APP'"
fi

# 6. Functional Check: Authorized traffic from frontend
FRONTEND_CONN=$(kubectl exec -n "$NAMESPACE" frontend-app -- wget -qO- --timeout=3 http://backend-svc:8080 2>&1 || echo "CONN_ERROR")
if echo "$FRONTEND_CONN" | grep -q -i -E "(directory|html|title|<body|python)"; then
  pass "Functional check: frontend-app successfully connected to backend-svc:8080"
else
  fail "Functional check: frontend-app failed to connect to backend-svc:8080" "Error: $FRONTEND_CONN"
fi

# 7. Functional Check: Unauthorized traffic from rogue pod in same namespace
ROGUE_CONN=$(kubectl exec -n "$NAMESPACE" rogue-client -- wget -qO- --timeout=3 http://backend-svc:8080 2>&1 || echo "TIMEOUT_OK")
if echo "$ROGUE_CONN" | grep -q -i -E "(download timed out|connection timed out|TIMEOUT_OK)"; then
  pass "Functional check: rogue-client was properly blocked by NetworkPolicy"
else
  fail "Security check failed: rogue-client was able to connect to backend-svc"
fi

# 8. Functional Check: Traffic from external namespace (analytics)
EXT_CONN=$(kubectl exec -n "$OTHER_NS" external-client -- wget -qO- --timeout=3 "http://backend-svc.${NAMESPACE}:8080" 2>&1 || echo "TIMEOUT_OK")
if echo "$EXT_CONN" | grep -q -i -E "(download timed out|connection timed out|TIMEOUT_OK)"; then
  pass "Functional check: external-client in separate namespace was properly blocked"
else
  fail "Security check failed: external-client was able to connect across namespaces"
fi

echo "==============================================="
echo -e "Total: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}SUCCESS! Lab passed.${NC}"
  exit 0
else
  echo -e "${RED}FAILURE! Review the requirements above.${NC}"
  exit 1
fi

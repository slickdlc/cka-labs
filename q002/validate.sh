#!/usr/bin/env bash
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

KUBE_SYSTEM="kube-system"
APP_NS="analytics"

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

echo "=== Evaluating Lab: Troubleshooting CoreDNS ==="

# 1. CoreDNS Deployment check (Available replicas)
AVAILABLE_REPLICAS=$(kubectl get deployment coredns -n "$KUBE_SYSTEM" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
DESIRED_REPLICAS=$(kubectl get deployment coredns -n "$KUBE_SYSTEM" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

if [ -n "$AVAILABLE_REPLICAS" ] && [ "$AVAILABLE_REPLICAS" -ge 1 ] && [ "$AVAILABLE_REPLICAS" -eq "$DESIRED_REPLICAS" ]; then
  pass "Deployment coredns has all desired replicas available ($AVAILABLE_REPLICAS/$DESIRED_REPLICAS)"
else
  fail "Deployment coredns does not have all replicas ready" "Available: ${AVAILABLE_REPLICAS:-0}, Desired: $DESIRED_REPLICAS"
fi

# 2. Check CoreDNS Pod statuses
CRASHING_PODS=$(kubectl get pods -n "$KUBE_SYSTEM" -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -iE "(CrashLoopBackOff|Error|ContainerCreating|Terminating|Pending)" || echo "")
if [ -z "$CRASHING_PODS" ]; then
  pass "All CoreDNS pods are Running and healthy"
else
  fail "Found CoreDNS pods in unhealthy/restarting states" "$CRASHING_PODS"
fi

# 3. Check syntax in ConfigMap 'coredns'
CM_COREFILE=$(kubectl get configmap coredns -n "$KUBE_SYSTEM" -o jsonpath='{.data.Corefile}' 2>/dev/null || echo "")
if echo "$CM_COREFILE" | grep -qE "(forwarders|kubernetess|invalid_directive)"; then
  fail "ConfigMap 'coredns' still contains invalid directives or typos" "Detected: $(echo "$CM_COREFILE" | grep -E '(forwarders|kubernetess|invalid_directive)')"
else
  pass "ConfigMap 'coredns' contains a valid Corefile configuration"
fi

# 4. Check Selector in Service 'kube-dns'
SVC_SELECTOR=$(kubectl get service kube-dns -n "$KUBE_SYSTEM" -o jsonpath='{.spec.selector.k8s-app}' 2>/dev/null || echo "")
DEPLOY_LABEL=$(kubectl get deployment coredns -n "$KUBE_SYSTEM" -o jsonpath='{.spec.template.metadata.labels.k8s-app}' 2>/dev/null || echo "kube-dns")

if [ "$SVC_SELECTOR" = "$DEPLOY_LABEL" ] && [ -n "$SVC_SELECTOR" ]; then
  pass "Service 'kube-dns' has matching selector pointing to 'k8s-app: $SVC_SELECTOR'"
else
  fail "Service 'kube-dns' has mismatched selector" "Current: '$SVC_SELECTOR', Expected: '$DEPLOY_LABEL'"
fi

# 5. Check Endpoints associated with 'kube-dns'
ENDPOINTS=$(kubectl get endpoints kube-dns -n "$KUBE_SYSTEM" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
if [ -n "$ENDPOINTS" ]; then
  pass "Service 'kube-dns' has backend pod IPs registered in Endpoints ($ENDPOINTS)"
else
  fail "Service 'kube-dns' has no endpoints mapped (<none>)" "Ensure the Service selector matches the CoreDNS pod template labels"
fi

# 6. Functional Test 1: Resolve internal app service in analytics namespace
DB_IP=$(kubectl get service database-svc -n "$APP_NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
NSLOOKUP_APP=$(kubectl exec -n "$APP_NS" data-processor -- nslookup database-svc 2>&1 || echo "LOOKUP_FAILED")

if echo "$NSLOOKUP_APP" | grep -q "$DB_IP" && [ -n "$DB_IP" ]; then
  pass "Functional check: 'data-processor' successfully resolved 'database-svc' to $DB_IP"
else
  fail "Functional check: 'data-processor' failed to resolve 'database-svc'" "Output: $NSLOOKUP_APP"
fi

# 7. Functional Test 2: Resolve cluster service 'kubernetes.default'
K8S_IP=$(kubectl get service kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
NSLOOKUP_K8S=$(kubectl exec -n "$APP_NS" data-processor -- nslookup kubernetes.default 2>&1 || echo "LOOKUP_FAILED")

if echo "$NSLOOKUP_K8S" | grep -q "$K8S_IP" && [ -n "$K8S_IP" ]; then
  pass "Functional check: 'data-processor' successfully resolved 'kubernetes.default' to $K8S_IP"
else
  fail "Functional check: 'data-processor' failed to resolve 'kubernetes.default'" "Output: $NSLOOKUP_K8S"
fi

echo "======================================================="
echo -e "Total: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}SUCCESS! The cluster DNS infrastructure has been successfully repaired.${NC}"
  exit 0
else
  echo -e "${RED}FAILURE! Review the components that failed validation above.${NC}"
  exit 1
fi

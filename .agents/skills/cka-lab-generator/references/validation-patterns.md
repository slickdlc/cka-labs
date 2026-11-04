# Robust Validation Patterns for CKA Labs (`validate.sh`)

This manual outlines bash validation patterns for assessing CKA lab solutions without false positives or reliance on brittle regular expressions.

---

## 1. Standard Structure of `validate.sh`

```bash
#!/usr/bin/env bash
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

echo "=== Starting CKA Lab Validation ==="

# --- CHECKS HERE ---

echo "==================================="
echo -e "Total: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}SUCCESS! Lab passed.${NC}"
  exit 0
else
  echo -e "${RED}FAILURE! One or more checks failed.${NC}"
  exit 1
fi
```

---

## 2. Declarative Validation via JSONPath

Always extract structured fields directly using JSONPath instead of parsing raw YAML with grep:

### Resource Existence
```bash
if kubectl get deployment my-deploy -n my-ns >/dev/null 2>&1; then
  pass "Deployment 'my-deploy' exists"
else
  fail "Deployment 'my-deploy' not found"
  exit 1
fi
```

### Labels and Selectors
```bash
SELECTOR=$(kubectl get service my-svc -n my-ns -o jsonpath='{.spec.selector.app}' 2>/dev/null || echo "")
if [ "$SELECTOR" = "backend" ]; then
  pass "Service selector matches 'app: backend'"
else
  fail "Service selector incorrect" "Current: '$SELECTOR', Expected: 'backend'"
fi
```

### Image and Replicas
```bash
IMAGE=$(kubectl get deployment my-deploy -n my-ns -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
REPLICAS=$(kubectl get deployment my-deploy -n my-ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

if [ "$IMAGE" = "nginx:1.25" ]; then
  pass "Container image matches 'nginx:1.25'"
else
  fail "Container image incorrect" "Current: '$IMAGE'"
fi

if [ "$REPLICAS" -ge 3 ]; then
  pass "At least 3 ready replicas running"
else
  fail "Insufficient ready replicas" "Current: $REPLICAS, Expected: >= 3"
fi
```

---

## 3. Functional Validation

### Network Connectivity (Egress / Ingress)
```bash
CONN_TEST=$(kubectl exec -n my-ns client-pod -- wget -qO- --timeout=3 http://backend-svc:8080 2>&1 || echo "CONN_TIMEOUT")
if echo "$CONN_TEST" | grep -qi "Welcome"; then
  pass "Client pod can reach backend-svc:8080"
else
  fail "Client pod failed to reach backend-svc:8080" "Output: $CONN_TEST"
fi
```

### DNS Resolution
```bash
RESOLV_TEST=$(kubectl exec -n my-ns client-pod -- nslookup backend-svc 2>&1 || echo "RESOLV_FAILED")
if echo "$RESOLV_TEST" | grep -q "$EXPECTED_IP"; then
  pass "DNS resolution succeeded for backend-svc"
else
  fail "DNS resolution failed for backend-svc" "Output: $RESOLV_TEST"
fi
```

### RBAC Permissions
```bash
if kubectl auth can-i create pods --as=system:serviceaccount:my-ns:deployer-sa -n my-ns | grep -qi "yes"; then
  pass "ServiceAccount has permission to create pods in 'my-ns'"
else
  fail "ServiceAccount cannot create pods in 'my-ns'"
fi

if kubectl auth can-i delete pods --as=system:serviceaccount:my-ns:deployer-sa -n my-ns | grep -qi "no"; then
  pass "ServiceAccount correctly restricted from deleting pods"
else
  fail "ServiceAccount unexpectedly has permission to delete pods"
fi
```

#!/usr/bin/env bash
set -uo pipefail

NAMESPACE="ecommerce-prod"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo -e "${BLUE}=== Evaluating CKA Lab: Cascading Workload Troubleshooting ===${NC}"

# Check 1: Namespace exists
if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  pass "Namespace '$NAMESPACE' exists"
else
  fail "Namespace '$NAMESPACE' does not exist"
  echo "Terminating further evaluation since target namespace is missing."
  exit 1
fi

# Check 2: Core dependency pods exist and remain Ready
DB_READY=$(kubectl get pod order-db -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
CLIENT_READY=$(kubectl get pod client-frontend -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

if [ "$DB_READY" = "true" ] && [ "$CLIENT_READY" = "true" ]; then
  pass "Dependency pods 'order-db' and 'client-frontend' are running and Ready"
else
  fail "Dependency pods are not in healthy Ready state (order-db: $DB_READY, client-frontend: $CLIENT_READY)"
fi

# Check 3: Secret db-credentials preserved with original key
SECRET_KEY=$(kubectl get secret db-credentials -n "$NAMESPACE" -o jsonpath='{.data.db_password}' 2>/dev/null || echo "")
if [ -n "$SECRET_KEY" ]; then
  pass "Secret 'db-credentials' contains required key 'db_password'"
else
  fail "Secret 'db-credentials' is missing required key 'db_password'" "Do not alter or delete the existing secret keys"
fi

# Check 4: Deployment order-service exists with 2 replicas
DEPLOY_SPEC_REPLICAS=$(kubectl get deploy order-service -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [ "$DEPLOY_SPEC_REPLICAS" -eq 2 ]; then
  pass "Deployment 'order-service' is configured with 2 desired replicas"
else
  fail "Deployment 'order-service' expected 2 desired replicas, found: $DEPLOY_SPEC_REPLICAS"
fi

# Check 5: Scheduling constraint (nodeSelector resolved)
UNSATISFIABLE_SELECTOR=$(kubectl get deploy order-service -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.nodeSelector.disktype}' 2>/dev/null || echo "")
if [ "$UNSATISFIABLE_SELECTOR" != "nvme-enterprise" ]; then
  pass "Invalid nodeSelector constraint 'disktype: nvme-enterprise' removed"
else
  fail "Deployment still contains unsatisfiable nodeSelector 'disktype: nvme-enterprise'" "Pods cannot schedule"
fi

# Check 6: Deployment pods are Running and Ready (2/2)
READY_REPLICAS=$(kubectl get deploy order-service -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
AVAILABLE_REPLICAS=$(kubectl get deploy order-service -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")

if [ "$READY_REPLICAS" -eq 2 ] && [ "$AVAILABLE_REPLICAS" -eq 2 ]; then
  pass "All 2 replicas of Deployment 'order-service' are in Running and Ready (1/1) state"
else
  fail "Deployment 'order-service' does not have 2 Ready replicas (readyReplicas: $READY_REPLICAS, availableReplicas: $AVAILABLE_REPLICAS)"
fi

# Check 7: Readiness probe configured to valid port and path
PROBE_PORT=$(kubectl get deploy order-service -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="order-app")].readinessProbe.httpGet.port}' 2>/dev/null || echo "")
PROBE_PATH=$(kubectl get deploy order-service -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="order-app")].readinessProbe.httpGet.path}' 2>/dev/null || echo "")

if ([ "$PROBE_PORT" = "80" ] || [ "$PROBE_PORT" = "http" ]) && [ "$PROBE_PATH" = "/" ]; then
  pass "Readiness probe properly targets container port 80 at path '/'"
else
  fail "Readiness probe misconfigured (port: '$PROBE_PORT', path: '$PROBE_PATH')" "Expected port 80 (or 'http') and path '/'"
fi

# Check 8: Container environment references correct secret key
ENV_KEY=$(kubectl get deploy order-service -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="order-app")].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.key}' 2>/dev/null || echo "")
if [ "$ENV_KEY" = "db_password" ]; then
  pass "Container env 'DB_PASSWORD' maps to correct secret key 'db_password'"
else
  fail "Container env 'DB_PASSWORD' maps to invalid key: '$ENV_KEY'" "Must map to secretKeyRef 'db_password'"
fi

# Check 9: Service selector matches backend pods
SVC_SELECTOR=$(kubectl get svc order-service -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}' 2>/dev/null || echo "")
if [ "$SVC_SELECTOR" = "order-backend" ]; then
  pass "Service 'order-service' selector matches pod label 'app=order-backend'"
else
  fail "Service 'order-service' selector mismatch: '$SVC_SELECTOR'" "Expected 'order-backend'"
fi

# Check 10: Service targetPort configured to 80
SVC_TARGET_PORT=$(kubectl get svc order-service -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "")
if [ "$SVC_TARGET_PORT" = "80" ] || [ "$SVC_TARGET_PORT" = "http" ]; then
  pass "Service 'order-service' targetPort maps to port 80"
else
  fail "Service 'order-service' targetPort invalid: '$SVC_TARGET_PORT'" "Expected 80 or 'http'"
fi

# Check 11: Service Endpoints are active and populated with 2 pod IPs
ENDPOINT_COUNT=$(kubectl get endpoints order-service -n "$NAMESPACE" -o jsonpath='{range .subsets[*]}{range .addresses[*]}{.ip}{"\n"}{end}{end}' 2>/dev/null | grep -c -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || echo "0")
if [ "$ENDPOINT_COUNT" -eq 2 ]; then
  pass "Service 'order-service' has 2 active healthy endpoints"
else
  fail "Service 'order-service' does not have 2 endpoints (found: $ENDPOINT_COUNT)" "Ensure pods are Ready and selector matches"
fi

# Check 12: NetworkPolicy exists and enforces Ingress and Egress
NETPOL_TYPES=$(kubectl get netpol order-netpol -n "$NAMESPACE" -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null || echo "")
if echo "$NETPOL_TYPES" | grep -q "Ingress" && echo "$NETPOL_TYPES" | grep -q "Egress"; then
  pass "NetworkPolicy 'order-netpol' actively manages both Ingress and Egress"
else
  fail "NetworkPolicy 'order-netpol' missing Ingress or Egress policyType: '$NETPOL_TYPES'"
fi

# Check 13 & 14: NetworkPolicy Declarative Ingress & Egress Rules
NETPOL_INGRESS_MATCH=$(kubectl get netpol order-netpol -n "$NAMESPACE" -o jsonpath='{.spec.ingress[*].from[*].podSelector.matchLabels.app}' 2>/dev/null || echo "")
if echo "$NETPOL_INGRESS_MATCH" | grep -q "client-frontend"; then
  pass "NetworkPolicy 'order-netpol' permits Ingress from pods labeled 'app=client-frontend'"
else
  fail "NetworkPolicy 'order-netpol' does not permit Ingress from 'app=client-frontend'" "Found: '$NETPOL_INGRESS_MATCH'"
fi

NETPOL_EGRESS_PORTS=$(kubectl get netpol order-netpol -n "$NAMESPACE" -o jsonpath='{.spec.egress[*].ports[*].port}' 2>/dev/null || echo "")
if echo "$NETPOL_EGRESS_PORTS" | grep -q "53" && echo "$NETPOL_EGRESS_PORTS" | grep -q "5432"; then
  pass "NetworkPolicy 'order-netpol' permits Egress on ports 53 (DNS) and 5432 (DB)"
else
  fail "NetworkPolicy 'order-netpol' missing Egress rules for port 53 or 5432 (found: '$NETPOL_EGRESS_PORTS')"
fi

# Check 15: Functional End-to-End Test (curl from client-frontend to order-service)
echo -e "${YELLOW}[TEST] Executing functional HTTP request from client-frontend to order-service...${NC}"
HTTP_RESPONSE=$(kubectl exec client-frontend -n "$NAMESPACE" -- curl -s -m 5 -w "\n%{http_code}" http://order-service.ecommerce-prod.svc.cluster.local:80/ 2>/dev/null || echo "FAILED")
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

if [ "$HTTP_CODE" = "200" ]; then
  pass "Functional E2E: 'client-frontend' successfully reached 'http://order-service' with HTTP 200 OK"
else
  fail "Functional E2E: HTTP request failed or timed out (HTTP code: '$HTTP_CODE')" "Response: $(echo "$HTTP_RESPONSE" | head -n 2)"
fi

echo -e "${BLUE}===================================================================${NC}"
echo -e "Total Checks: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}SUCCESS! All CKA expert troubleshooting requirements satisfied.${NC}"
  exit 0
else
  echo -e "${RED}FAILURE! One or more troubleshooting checks failed.${NC}"
  exit 1
fi

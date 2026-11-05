#!/usr/bin/env bash
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="argocd"
RELEASE_NAME="argocd"
EXPECTED_CHART_VERSION="7.7.3"
TEMPLATE_FILE="/argo-helm.yaml"

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
echo "=== Validating Lab: Argo CD Helm Installation & Config ==="
echo "=========================================================="

# ---------------------------------------------------------
# Check 1: Helm CLI Availability
# ---------------------------------------------------------
if command -v helm &>/dev/null; then
  pass "Helm CLI is installed and accessible"
else
  fail "Helm CLI is not installed or not found on PATH" "Required for Helm release validation"
fi

# ---------------------------------------------------------
# Check 2: Helm Repository 'argo' Configured
# ---------------------------------------------------------
REPO_URL=$(helm repo list -o json 2>/dev/null | grep -o '"url": *"[^"]*"' | grep 'argo-helm' | head -n 1 || echo "")
REPO_NAME_CHECK=$(helm repo list 2>/dev/null | awk '$1 == "argo" {print $1}' || echo "")

if [ "$REPO_NAME_CHECK" = "argo" ]; then
  pass "Helm repository 'argo' is registered"
  if helm repo list 2>/dev/null | grep -E "argo[[:space:]]+https://argoproj\.github\.io/argo-helm" &>/dev/null; then
    pass "Helm repository 'argo' points to 'https://argoproj.github.io/argo-helm'"
  else
    fail "Helm repository 'argo' URL mismatch" "Expected: https://argoproj.github.io/argo-helm"
  fi
else
  fail "Helm repository 'argo' is not registered" "Run: helm repo add argo https://argoproj.github.io/argo-helm"
fi

# ---------------------------------------------------------
# Check 3: Pre-installed Argo CD CRDs exist
# ---------------------------------------------------------
CRD_APPS=$(kubectl get crd applications.argoproj.io --ignore-not-found -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
CRD_APPSETS=$(kubectl get crd applicationsets.argoproj.io --ignore-not-found -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
CRD_PROJECTS=$(kubectl get crd appprojects.argoproj.io --ignore-not-found -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

if [ "$CRD_APPS" = "applications.argoproj.io" ] && [ "$CRD_APPSETS" = "applicationsets.argoproj.io" ] && [ "$CRD_PROJECTS" = "appprojects.argoproj.io" ]; then
  pass "Argo CD CRDs exist in the cluster"
else
  fail "One or more Argo CD CRDs are missing" "Found: applications='$CRD_APPS', appsets='$CRD_APPSETS', projects='$CRD_PROJECTS'"
fi

# ---------------------------------------------------------
# Check 4: Helm Template File Existence at /argo-helm.yaml
# ---------------------------------------------------------
if [ -f "$TEMPLATE_FILE" ]; then
  if [ -s "$TEMPLATE_FILE" ]; then
    pass "Rendered template file '$TEMPLATE_FILE' exists and is non-empty"
  else
    fail "Rendered template file '$TEMPLATE_FILE' exists but is empty" "File size is 0 bytes"
  fi
else
  fail "Rendered template file '$TEMPLATE_FILE' does not exist" "Expected path: /argo-helm.yaml"
fi

# ---------------------------------------------------------
# Check 5: Helm Template File Contents & Configuration
# ---------------------------------------------------------
if [ -f "$TEMPLATE_FILE" ] && [ -s "$TEMPLATE_FILE" ]; then
  # 5a. Check that CRDs are NOT included in the rendered template
  if grep -E "^kind:[[:space:]]*CustomResourceDefinition" "$TEMPLATE_FILE" &>/dev/null; then
    fail "Rendered template contains CustomResourceDefinitions (CRDs)" "Template was not configured to skip/disable CRDs"
  else
    pass "Rendered template correctly excludes CustomResourceDefinitions (CRDs)"
  fi

  # 5b. Check that core Argo CD resources are present in template
  if grep -E "argocd-server|argocd-repo-server" "$TEMPLATE_FILE" &>/dev/null; then
    pass "Rendered template contains core Argo CD components"
  else
    fail "Rendered template does not appear to contain Argo CD components" "Check template generation command"
  fi

  # 5c. Check namespace defined in template
  if grep -E "namespace:[[:space:]]*argocd" "$TEMPLATE_FILE" &>/dev/null; then
    pass "Rendered template specifies namespace '$NAMESPACE'"
  else
    fail "Rendered template does not explicitly reference namespace '$NAMESPACE'" "Use --namespace argocd during templating"
  fi
fi

# ---------------------------------------------------------
# Check 6: Helm Release in Namespace 'argocd'
# ---------------------------------------------------------
RELEASE_STATUS=$(helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json 2>/dev/null | grep -o '"status": *"[^"]*"' | head -n 1 || echo "")
if echo "$RELEASE_STATUS" | grep -qi "deployed"; then
  pass "Helm release '$RELEASE_NAME' is installed with status 'deployed' in namespace '$NAMESPACE'"
else
  fail "Helm release '$RELEASE_NAME' is not deployed in namespace '$NAMESPACE'" "Run: helm list -n $NAMESPACE"
fi

# ---------------------------------------------------------
# Check 7: Chart Version 7.7.3
# ---------------------------------------------------------
CHART_STRING=$(helm list -n "$NAMESPACE" -o json 2>/dev/null | grep -o '"chart": *"[^"]*"' | head -n 1 || echo "")
if echo "$CHART_STRING" | grep -q "$EXPECTED_CHART_VERSION"; then
  pass "Helm release uses Argo CD chart version '$EXPECTED_CHART_VERSION'"
else
  fail "Helm release chart version does not match '$EXPECTED_CHART_VERSION'" "Actual chart metadata: $CHART_STRING"
fi

# ---------------------------------------------------------
# Check 8: Release Values Configuration (CRDs Disabled)
# ---------------------------------------------------------
CRD_VALUE=$(helm get values "$RELEASE_NAME" -n "$NAMESPACE" -a 2>/dev/null | grep -E "crds:" -A 1 | grep "install:" | awk '{print $2}' || echo "")
if [ "$CRD_VALUE" = "false" ] || [ "$CRD_VALUE" = "False" ]; then
  pass "Helm release values explicitly configure 'crds.install: false'"
else
  # If values don't show crds.install: false, check user values
  USER_CRD_VALUE=$(helm get values "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null | grep -E "install:" | awk '{print $2}' || echo "")
  if [ "$USER_CRD_VALUE" = "false" ] || [ "$USER_CRD_VALUE" = "False" ]; then
    pass "Helm release user values explicitly configure 'crds.install: false'"
  else
    fail "Helm release is not configured with 'crds.install=false'" "Values show: crds.install=${CRD_VALUE:-unset}"
  fi
fi

# ---------------------------------------------------------
# Check 9: Target Namespace Workloads Running/Available
# ---------------------------------------------------------
SERVER_DEPLOY=$(kubectl get deployment argocd-server -n "$NAMESPACE" --ignore-not-found -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
REPO_DEPLOY=$(kubectl get deployment argocd-repo-server -n "$NAMESPACE" --ignore-not-found -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

if [ "$SERVER_DEPLOY" = "argocd-server" ] && [ "$REPO_DEPLOY" = "argocd-repo-server" ]; then
  pass "Core Argo CD deployments ('argocd-server', 'argocd-repo-server') deployed in namespace '$NAMESPACE'"
else
  fail "Argo CD deployments missing in namespace '$NAMESPACE'" "server: '$SERVER_DEPLOY', repo-server: '$REPO_DEPLOY'"
fi

# ---------------------------------------------------------
# Evaluation Summary
# ---------------------------------------------------------
echo "=========================================================="
echo -e "Total Checks: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"
echo "=========================================================="

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}>>> LAB EVALUATION: SUCCESSFUL (100% Satisfied) <<<${NC}"
  exit 0
else
  echo -e "${RED}>>> LAB EVALUATION: FAILED (Review discrepancies above) <<<${NC}"
  exit 1
fi

#!/bin/bash
#===============================================================================
# Kubernetes Security Audit Script
# Runs comprehensive security checks using kube-bench, Trivy, and kubectl
#
# Usage:
#   ./security-audit.sh full                # Run all checks
#   ./security-audit.sh cis                 # CIS Benchmark (kube-bench)
#   ./security-audit.sh images              # Scan images for vulnerabilities
#   ./security-audit.sh rbac                # RBAC audit
#   ./security-audit.sh pods                # Pod security audit
#   ./security-audit.sh network             # Network security audit
#   ./security-audit.sh secrets             # Secrets audit
#===============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-/tmp/k8s-security-audit-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$REPORT_DIR"

header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# CIS BENCHMARK (kube-bench)
#-------------------------------------------------------------------------------
audit_cis() {
    header "CIS KUBERNETES BENCHMARK (kube-bench)"

    if command -v kube-bench &> /dev/null; then
        echo -e "${YELLOW}Running kube-bench...${NC}"
        kube-bench run --targets master,node 2>&1 | tee "$REPORT_DIR/cis-benchmark.txt"
    elif kubectl get nodes &> /dev/null; then
        echo -e "${YELLOW}Running kube-bench as a Job in the cluster...${NC}"
        kubectl apply -f - << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench
  namespace: default
spec:
  template:
    spec:
      hostPID: true
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: ["kube-bench"]
        volumeMounts:
        - name: var-lib-etcd
          mountPath: /var/lib/etcd
          readOnly: true
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
          readOnly: true
        - name: etc-systemd
          mountPath: /etc/systemd
          readOnly: true
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
      restartPolicy: Never
      volumes:
      - name: var-lib-etcd
        hostPath:
          path: /var/lib/etcd
      - name: var-lib-kubelet
        hostPath:
          path: /var/lib/kubelet
      - name: etc-systemd
        hostPath:
          path: /etc/systemd
      - name: etc-kubernetes
        hostPath:
          path: /etc/kubernetes
EOF
        echo -e "${YELLOW}Waiting for kube-bench job to complete...${NC}"
        kubectl wait --for=condition=complete job/kube-bench --timeout=300s
        kubectl logs job/kube-bench | tee "$REPORT_DIR/cis-benchmark.txt"
        kubectl delete job kube-bench
    else
        echo -e "${RED}kube-bench not found. Install it or run as a cluster Job.${NC}"
    fi
}

#-------------------------------------------------------------------------------
# IMAGE VULNERABILITY SCANNING
#-------------------------------------------------------------------------------
audit_images() {
    header "CONTAINER IMAGE VULNERABILITY SCAN"

    # Get all unique images in the cluster
    echo -e "${YELLOW}Collecting all container images in the cluster...${NC}"
    IMAGES=$(kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u)

    echo -e "${GREEN}Found $(echo "$IMAGES" | wc -l) unique images${NC}"
    echo "$IMAGES" | tee "$REPORT_DIR/images-list.txt"
    echo ""

    if command -v trivy &> /dev/null; then
        echo -e "${YELLOW}Scanning images with Trivy...${NC}"
        while IFS= read -r image; do
            echo -e "${CYAN}━━━ Scanning: ${image} ━━━${NC}"
            trivy image --severity HIGH,CRITICAL --no-progress "$image" 2>&1 | tee -a "$REPORT_DIR/trivy-scan.txt" || true
            echo ""
        done <<< "$IMAGES"
    else
        echo -e "${YELLOW}Trivy not installed. Install with:${NC}"
        echo "  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin"
        echo ""
        echo -e "${YELLOW}Checking for known vulnerable base images...${NC}"
        while IFS= read -r image; do
            # Flag images using :latest tag
            if echo "$image" | grep -q ":latest\|:[[:space:]]*$"; then
                echo -e "  ${RED}⚠️  Using :latest tag: ${image}${NC}"
            fi
        done <<< "$IMAGES"
    fi
}

#-------------------------------------------------------------------------------
# RBAC AUDIT
#-------------------------------------------------------------------------------
audit_rbac() {
    header "RBAC SECURITY AUDIT"

    echo -e "${YELLOW}[1] ClusterRoleBindings with cluster-admin role:${NC}"
    kubectl get clusterrolebindings -o json | \
        jq -r '.items[] | select(.roleRef.name=="cluster-admin") | 
        "  \(.metadata.name) → Subjects: \([.subjects[]? | "\(.kind)/\(.name)(\(.namespace // "cluster-wide"))"] | join(", "))"'
    echo ""

    echo -e "${YELLOW}[2] ServiceAccounts with secrets:${NC}"
    kubectl get serviceaccounts -A -o json | \
        jq -r '.items[] | select(.secrets != null and (.secrets | length > 0)) |
        "  \(.metadata.namespace)/\(.metadata.name) → \(.secrets | length) secret(s)"' 2>/dev/null || \
    kubectl get serviceaccounts -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name"
    echo ""

    echo -e "${YELLOW}[3] Pods running with automountServiceAccountToken (not disabled):${NC}"
    kubectl get pods -A -o json | \
        jq -r '.items[] | select(.spec.automountServiceAccountToken != false) |
        "  \(.metadata.namespace)/\(.metadata.name) → SA: \(.spec.serviceAccountName // "default")"' | head -20
    echo ""

    echo -e "${YELLOW}[4] Roles/ClusterRoles with wildcard permissions:${NC}"
    kubectl get clusterroles -o json | \
        jq -r '.items[] | select(.rules[]? | .resources[]? == "*" or .verbs[]? == "*") |
        "  ⚠️  \(.metadata.name)"' 2>/dev/null || echo "  Unable to check"
    echo ""

    echo -e "${YELLOW}[5] Can anonymous users access the API?${NC}"
    kubectl auth can-i --list --as=system:anonymous 2>/dev/null | head -10 || echo "  Cannot check"

    # Save report
    kubectl get clusterrolebindings,rolebindings -A -o wide > "$REPORT_DIR/rbac-bindings.txt" 2>/dev/null
}

#-------------------------------------------------------------------------------
# POD SECURITY AUDIT
#-------------------------------------------------------------------------------
audit_pods() {
    header "POD SECURITY AUDIT"

    echo -e "${YELLOW}[1] Pods running as root (UID 0):${NC}"
    kubectl get pods -A -o json | \
        jq -r '.items[] | select(
            .spec.containers[]?.securityContext?.runAsUser == 0 or
            (.spec.securityContext?.runAsUser == 0) or
            (.spec.containers[]?.securityContext?.runAsNonRoot != true and .spec.securityContext?.runAsNonRoot != true)
        ) | "  ⚠️  \(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | head -20
    echo ""

    echo -e "${YELLOW}[2] Privileged containers:${NC}"
    kubectl get pods -A -o json | \
        jq -r '.items[] | select(.spec.containers[]?.securityContext?.privileged == true) |
        "  🔴 \(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "  None found or unable to check"
    echo ""

    echo -e "${YELLOW}[3] Containers with privilege escalation allowed:${NC}"
    kubectl get pods -A -o json | \
        jq -r '.items[] | select(.spec.containers[]?.securityContext?.allowPrivilegeEscalation != false) |
        "  ⚠️  \(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | head -20
    echo ""

    echo -e "${YELLOW}[4] Pods without resource limits:${NC}"
    kubectl get pods -A -o json | \
        jq -r '.items[] | select(.spec.containers[]? | .resources.limits == null) |
        "  ⚠️  \(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | head -20
    echo ""

    echo -e "${YELLOW}[5] Pods with hostNetwork/hostPID/hostIPC:${NC}"
    kubectl get pods -A -o json | \
        jq -r '.items[] | select(.spec.hostNetwork == true or .spec.hostPID == true or .spec.hostIPC == true) |
        "  🔴 \(.metadata.namespace)/\(.metadata.name) hostNet=\(.spec.hostNetwork) hostPID=\(.spec.hostPID) hostIPC=\(.spec.hostIPC)"' 2>/dev/null || echo "  None found"
    echo ""
}

#-------------------------------------------------------------------------------
# NETWORK SECURITY AUDIT
#-------------------------------------------------------------------------------
audit_network() {
    header "NETWORK SECURITY AUDIT"

    echo -e "${YELLOW}[1] Namespaces WITHOUT any NetworkPolicies:${NC}"
    ALL_NS=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
    for ns in $ALL_NS; do
        count=$(kubectl get networkpolicies -n "$ns" --no-headers 2>/dev/null | wc -l)
        if [ "$count" -eq 0 ]; then
            echo -e "  ⚠️  ${ns} — No NetworkPolicies (all traffic allowed)"
        fi
    done
    echo ""

    echo -e "${YELLOW}[2] Existing NetworkPolicies:${NC}"
    kubectl get networkpolicies -A -o custom-columns=\
"NAMESPACE:.metadata.namespace,NAME:.metadata.name,POD-SELECTOR:.spec.podSelector,POLICY-TYPES:.spec.policyTypes[*]"
    echo ""

    echo -e "${YELLOW}[3] Services exposed externally (NodePort/LoadBalancer):${NC}"
    kubectl get services -A -o json | \
        jq -r '.items[] | select(.spec.type == "NodePort" or .spec.type == "LoadBalancer") |
        "  \(.spec.type): \(.metadata.namespace)/\(.metadata.name) → Ports: \([.spec.ports[]? | "\(.port):\(.nodePort // .port)"] | join(","))"'
    echo ""

    echo -e "${YELLOW}[4] Ingress resources:${NC}"
    kubectl get ingress -A -o custom-columns=\
"NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTS:.spec.rules[*].host,TLS:.spec.tls[*].hosts[*]" 2>/dev/null || echo "  No ingress resources found"
    echo ""
}

#-------------------------------------------------------------------------------
# SECRETS AUDIT
#-------------------------------------------------------------------------------
audit_secrets() {
    header "SECRETS SECURITY AUDIT"

    echo -e "${YELLOW}[1] Secrets count by namespace:${NC}"
    for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
        count=$(kubectl get secrets -n "$ns" --no-headers 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            echo "  $ns: $count secrets"
        fi
    done
    echo ""

    echo -e "${YELLOW}[2] Secrets of type Opaque (user-created):${NC}"
    kubectl get secrets -A --field-selector=type=Opaque -o custom-columns=\
"NAMESPACE:.metadata.namespace,NAME:.metadata.name,AGE:.metadata.creationTimestamp"
    echo ""

    echo -e "${YELLOW}[3] Checking if etcd encryption is configured:${NC}"
    if [ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
        if grep -q "encryption-provider-config" /etc/kubernetes/manifests/kube-apiserver.yaml; then
            echo -e "  ${GREEN}✅ Encryption at rest is configured${NC}"
            grep "encryption-provider-config" /etc/kubernetes/manifests/kube-apiserver.yaml
        else
            echo -e "  ${RED}❌ Encryption at rest is NOT configured${NC}"
            echo -e "  ${YELLOW}   Secrets are stored in plain text in etcd!${NC}"
        fi
    else
        echo -e "  ${YELLOW}  Cannot check (no access to API server manifest)${NC}"
    fi
    echo ""
}

#-------------------------------------------------------------------------------
# FULL AUDIT
#-------------------------------------------------------------------------------
audit_full() {
    header "FULL KUBERNETES SECURITY AUDIT"
    echo -e "${YELLOW}Report directory: ${REPORT_DIR}${NC}"

    audit_rbac
    audit_pods
    audit_network
    audit_secrets
    audit_images
    audit_cis

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  AUDIT COMPLETE                                  ║${NC}"
    echo -e "${GREEN}║  Reports saved to: ${REPORT_DIR}   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
case "${1:-help}" in
    full)     audit_full ;;
    cis)      audit_cis ;;
    images)   audit_images ;;
    rbac)     audit_rbac ;;
    pods)     audit_pods ;;
    network)  audit_network ;;
    secrets)  audit_secrets ;;
    *)
        echo "Kubernetes Security Audit Script"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  full      Run all security checks"
        echo "  cis       CIS Benchmark with kube-bench"
        echo "  images    Scan container images for vulnerabilities"
        echo "  rbac      RBAC permissions audit"
        echo "  pods      Pod security configuration audit"
        echo "  network   Network policies and exposure audit"
        echo "  secrets   Secrets management audit"
        echo ""
        echo "Reports are saved to: \$REPORT_DIR (default: /tmp/k8s-security-audit-*)"
        ;;
esac


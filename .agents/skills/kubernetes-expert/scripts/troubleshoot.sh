#!/bin/bash
#===============================================================================
# Kubernetes Cluster Troubleshooting Script
# Automated diagnostics and health checks
#
# Usage:
#   ./troubleshoot.sh all                    # Full cluster diagnostics
#   ./troubleshoot.sh nodes                  # Node health check
#   ./troubleshoot.sh pods [namespace]       # Pod diagnostics
#   ./troubleshoot.sh services [namespace]   # Service & endpoint check
#   ./troubleshoot.sh dns                    # DNS resolution test
#   ./troubleshoot.sh control-plane          # Control plane health
#   ./troubleshoot.sh events [namespace]     # Recent events
#   ./troubleshoot.sh resources [namespace]  # Resource usage
#   ./troubleshoot.sh storage [namespace]    # Storage diagnostics
#===============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

NS="${2:---all-namespaces}"
[ "$NS" != "--all-namespaces" ] && NS="-n $NS"

header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# NODE DIAGNOSTICS
#-------------------------------------------------------------------------------
check_nodes() {
    header "NODE HEALTH CHECK"

    echo -e "${YELLOW}[1] Node Status:${NC}"
    kubectl get nodes -o wide
    echo ""

    echo -e "${YELLOW}[2] Node Conditions:${NC}"
    kubectl get nodes -o json | jq -r '
        .items[] | 
        "\(.metadata.name):" + 
        ([.status.conditions[] | 
            select(.status != "False" or .type == "Ready") | 
            "  \(.type)=\(.status) (\(.reason // "unknown"))"
        ] | join("\n"))
    '
    echo ""

    echo -e "${YELLOW}[3] Node Resource Usage:${NC}"
    kubectl top nodes 2>/dev/null || echo "  Metrics server not available"
    echo ""

    echo -e "${YELLOW}[4] Node Taints:${NC}"
    kubectl get nodes -o json | jq -r '
        .items[] | 
        "\(.metadata.name): \([.spec.taints[]? | "\(.key)=\(.value // ""):\(.effect)"] | join(", ") // "No taints")"
    '
    echo ""

    echo -e "${YELLOW}[5] NotReady Nodes (if any):${NC}"
    NOTREADY=$(kubectl get nodes --field-selector=status.phase!=Running -o name 2>/dev/null || true)
    if kubectl get nodes | grep -q "NotReady"; then
        kubectl get nodes | grep "NotReady"
        echo ""
        echo -e "${RED}  Troubleshooting steps for NotReady nodes:${NC}"
        echo "  1. SSH to the node and check: systemctl status kubelet"
        echo "  2. Check kubelet logs: journalctl -u kubelet -n 50"
        echo "  3. Check container runtime: systemctl status containerd"
        echo "  4. Check certificates: openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -dates"
        echo "  5. Check disk: df -h"
    else
        echo -e "  ${GREEN}✅ All nodes are Ready${NC}"
    fi
}

#-------------------------------------------------------------------------------
# POD DIAGNOSTICS
#-------------------------------------------------------------------------------
check_pods() {
    header "POD DIAGNOSTICS"

    echo -e "${YELLOW}[1] Pods NOT Running/Completed:${NC}"
    kubectl get pods $NS --field-selector=status.phase!=Running,status.phase!=Succeeded -o wide 2>/dev/null || \
    kubectl get pods $NS | grep -v "Running\|Completed\|NAME" || echo "  All pods are healthy!"
    echo ""

    echo -e "${YELLOW}[2] Pods with restarts > 0:${NC}"
    kubectl get pods $NS -o json | jq -r '
        .items[] | 
        select(.status.containerStatuses[]?.restartCount > 0) |
        "  \(.metadata.namespace)/\(.metadata.name) — Restarts: \([.status.containerStatuses[]? | "\(.name):\(.restartCount)"] | join(", "))"
    ' 2>/dev/null | head -20
    echo ""

    echo -e "${YELLOW}[3] Pending Pods (scheduling issues):${NC}"
    PENDING=$(kubectl get pods $NS --field-selector=status.phase=Pending -o json 2>/dev/null)
    echo "$PENDING" | jq -r '.items[] | "  \(.metadata.namespace)/\(.metadata.name): \(.status.conditions[]?.message // "Unknown")"' 2>/dev/null || echo "  No pending pods"
    echo ""

    echo -e "${YELLOW}[4] CrashLoopBackOff Pods:${NC}"
    kubectl get pods $NS | grep "CrashLoopBackOff" || echo "  None"
    echo ""

    echo -e "${YELLOW}[5] ImagePullBackOff Pods:${NC}"
    kubectl get pods $NS | grep "ImagePull\|ErrImagePull" || echo "  None"
    echo ""

    echo -e "${YELLOW}[6] Evicted Pods:${NC}"
    kubectl get pods $NS --field-selector=status.phase=Failed -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.reason == "Evicted") | "  \(.metadata.namespace)/\(.metadata.name): \(.status.message)"' || echo "  None"
    echo ""

    echo -e "${YELLOW}[7] Pod Resource Usage (top consumers):${NC}"
    kubectl top pods $NS --sort-by=cpu 2>/dev/null | head -15 || echo "  Metrics server not available"
}

#-------------------------------------------------------------------------------
# SERVICE & ENDPOINT DIAGNOSTICS
#-------------------------------------------------------------------------------
check_services() {
    header "SERVICE & ENDPOINT DIAGNOSTICS"

    echo -e "${YELLOW}[1] Services with no endpoints (potential issues):${NC}"
    for svc in $(kubectl get services $NS --no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" 2>/dev/null | tr -s ' ' '/'); do
        ns=$(echo "$svc" | cut -d'/' -f1)
        name=$(echo "$svc" | cut -d'/' -f2)
        ep_count=$(kubectl get endpoints "$name" -n "$ns" -o json 2>/dev/null | jq '.subsets[]?.addresses // [] | length' 2>/dev/null || echo "0")
        if [ "$ep_count" = "0" ] || [ -z "$ep_count" ]; then
            svc_type=$(kubectl get service "$name" -n "$ns" -o jsonpath='{.spec.type}' 2>/dev/null)
            selector=$(kubectl get service "$name" -n "$ns" -o jsonpath='{.spec.selector}' 2>/dev/null)
            echo -e "  ${RED}⚠️  ${ns}/${name} (${svc_type}) — 0 endpoints, selector: ${selector}${NC}"
        fi
    done
    echo ""

    echo -e "${YELLOW}[2] All Services:${NC}"
    kubectl get services $NS -o wide
    echo ""
}

#-------------------------------------------------------------------------------
# DNS DIAGNOSTICS
#-------------------------------------------------------------------------------
check_dns() {
    header "DNS DIAGNOSTICS"

    echo -e "${YELLOW}[1] CoreDNS pods:${NC}"
    kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
    echo ""

    echo -e "${YELLOW}[2] CoreDNS service:${NC}"
    kubectl get svc -n kube-system kube-dns
    echo ""

    echo -e "${YELLOW}[3] CoreDNS ConfigMap:${NC}"
    kubectl get configmap coredns -n kube-system -o yaml 2>/dev/null | head -30
    echo ""

    echo -e "${YELLOW}[4] Testing DNS resolution from a debug pod:${NC}"
    echo "  Running: nslookup kubernetes.default.svc.cluster.local"
    kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -- \
        nslookup kubernetes.default.svc.cluster.local 2>/dev/null || \
        echo "  Could not run DNS test pod (may need manual testing)"
    echo ""
}

#-------------------------------------------------------------------------------
# CONTROL PLANE DIAGNOSTICS
#-------------------------------------------------------------------------------
check_control_plane() {
    header "CONTROL PLANE DIAGNOSTICS"

    echo -e "${YELLOW}[1] Control plane pods:${NC}"
    kubectl get pods -n kube-system -l tier=control-plane -o wide 2>/dev/null || \
    kubectl get pods -n kube-system | grep -E "kube-apiserver|kube-controller|kube-scheduler|etcd"
    echo ""

    echo -e "${YELLOW}[2] API Server health:${NC}"
    kubectl get --raw='/healthz' 2>/dev/null && echo "" || echo "  Cannot reach API server healthz"
    echo ""

    echo -e "${YELLOW}[3] API Server readiness (verbose):${NC}"
    kubectl get --raw='/readyz?verbose' 2>/dev/null | head -30 || echo "  Cannot check readiness"
    echo ""

    echo -e "${YELLOW}[4] etcd health (if accessible):${NC}"
    if command -v etcdctl &> /dev/null; then
        ETCDCTL_API=3 etcdctl \
            --endpoints=https://127.0.0.1:2379 \
            --cacert=/etc/kubernetes/pki/etcd/ca.crt \
            --cert=/etc/kubernetes/pki/etcd/server.crt \
            --key=/etc/kubernetes/pki/etcd/server.key \
            endpoint health 2>/dev/null || echo "  Cannot reach etcd"
    else
        echo "  etcdctl not available on this node"
    fi
    echo ""

    echo -e "${YELLOW}[5] Static pod manifests:${NC}"
    if [ -d /etc/kubernetes/manifests ]; then
        ls -la /etc/kubernetes/manifests/
    else
        echo "  Not on a control plane node (no /etc/kubernetes/manifests/)"
    fi
    echo ""

    echo -e "${YELLOW}[6] Certificates expiration:${NC}"
    kubeadm certs check-expiration 2>/dev/null || echo "  Cannot check (kubeadm not available or not on CP node)"
}

#-------------------------------------------------------------------------------
# EVENTS
#-------------------------------------------------------------------------------
check_events() {
    header "RECENT EVENTS (last 30 minutes)"

    echo -e "${YELLOW}Warning Events:${NC}"
    kubectl get events $NS --sort-by='.lastTimestamp' --field-selector=type=Warning 2>/dev/null | tail -30
    echo ""

    echo -e "${YELLOW}All Recent Events:${NC}"
    kubectl get events $NS --sort-by='.lastTimestamp' 2>/dev/null | tail -30
}

#-------------------------------------------------------------------------------
# RESOURCE USAGE
#-------------------------------------------------------------------------------
check_resources() {
    header "RESOURCE USAGE"

    echo -e "${YELLOW}[1] Node capacity vs allocatable:${NC}"
    kubectl get nodes -o json | jq -r '
        .items[] |
        "Node: \(.metadata.name)\n  CPU:    capacity=\(.status.capacity.cpu) allocatable=\(.status.allocatable.cpu)\n  Memory: capacity=\(.status.capacity.memory) allocatable=\(.status.allocatable.memory)\n  Pods:   capacity=\(.status.capacity.pods) allocatable=\(.status.allocatable.pods)\n"
    '
    echo ""

    echo -e "${YELLOW}[2] Resource Quotas:${NC}"
    kubectl get resourcequotas $NS 2>/dev/null || echo "  No resource quotas found"
    echo ""

    echo -e "${YELLOW}[3] LimitRanges:${NC}"
    kubectl get limitranges $NS 2>/dev/null || echo "  No LimitRanges found"
    echo ""
}

#-------------------------------------------------------------------------------
# STORAGE DIAGNOSTICS
#-------------------------------------------------------------------------------
check_storage() {
    header "STORAGE DIAGNOSTICS"

    echo -e "${YELLOW}[1] PersistentVolumes:${NC}"
    kubectl get pv -o wide 2>/dev/null || echo "  No PVs found"
    echo ""

    echo -e "${YELLOW}[2] PersistentVolumeClaims:${NC}"
    kubectl get pvc $NS -o wide 2>/dev/null || echo "  No PVCs found"
    echo ""

    echo -e "${YELLOW}[3] PVCs NOT Bound:${NC}"
    kubectl get pvc $NS -o json 2>/dev/null | jq -r '
        .items[] | select(.status.phase != "Bound") |
        "  ⚠️  \(.metadata.namespace)/\(.metadata.name) — Status: \(.status.phase)"
    ' || echo "  All PVCs are bound"
    echo ""

    echo -e "${YELLOW}[4] StorageClasses:${NC}"
    kubectl get storageclass 2>/dev/null || echo "  No StorageClasses found"
    echo ""
}

#-------------------------------------------------------------------------------
# FULL DIAGNOSTICS
#-------------------------------------------------------------------------------
check_all() {
    header "FULL CLUSTER DIAGNOSTICS"
    echo -e "${YELLOW}Cluster: $(kubectl config current-context)${NC}"
    echo -e "${YELLOW}Time: $(date)${NC}"

    check_nodes
    check_control_plane
    check_pods
    check_services
    check_dns
    check_events
    check_resources
    check_storage

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  DIAGNOSTICS COMPLETE${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
case "${1:-help}" in
    all)            check_all ;;
    nodes)          check_nodes ;;
    pods)           check_pods ;;
    services)       check_services ;;
    dns)            check_dns ;;
    control-plane)  check_control_plane ;;
    events)         check_events ;;
    resources)      check_resources ;;
    storage)        check_storage ;;
    *)
        echo "Kubernetes Cluster Troubleshooting Script"
        echo ""
        echo "Usage: $0 <command> [namespace]"
        echo ""
        echo "Commands:"
        echo "  all                  Full cluster diagnostics"
        echo "  nodes                Node health check"
        echo "  pods [namespace]     Pod diagnostics"
        echo "  services [namespace] Service & endpoint check"
        echo "  dns                  DNS resolution test"
        echo "  control-plane        Control plane health"
        echo "  events [namespace]   Recent events"
        echo "  resources [namespace] Resource usage"
        echo "  storage [namespace]  Storage diagnostics"
        echo ""
        echo "If namespace is omitted, checks all namespaces."
        ;;
esac


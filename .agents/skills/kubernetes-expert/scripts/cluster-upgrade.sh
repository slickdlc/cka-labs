#!/bin/bash
#===============================================================================
# Kubernetes Cluster Upgrade Script (kubeadm)
# Step-by-step upgrade procedure following official documentation
#
# Usage:
#   ./cluster-upgrade.sh plan                    # Check available upgrades
#   ./cluster-upgrade.sh upgrade-cp <version>    # Upgrade first control plane
#   ./cluster-upgrade.sh upgrade-cp2 <version>   # Upgrade additional control planes
#   ./cluster-upgrade.sh upgrade-worker <node> <version>  # Upgrade worker node
#   ./cluster-upgrade.sh verify                  # Verify cluster state
#===============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# PLAN: Check available upgrade versions
#-------------------------------------------------------------------------------
do_plan() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     KUBERNETES UPGRADE PLAN                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}Current cluster version:${NC}"
    kubectl get nodes -o wide
    echo ""

    echo -e "${YELLOW}Current kubeadm version:${NC}"
    kubeadm version -o short
    echo ""

    echo -e "${YELLOW}Available kubeadm versions:${NC}"
    if command -v apt-cache &> /dev/null; then
        apt-cache madison kubeadm | head -20
    elif command -v yum &> /dev/null; then
        yum list --showduplicates kubeadm | tail -20
    fi
    echo ""

    echo -e "${YELLOW}Upgrade plan:${NC}"
    sudo kubeadm upgrade plan
}

#-------------------------------------------------------------------------------
# UPGRADE FIRST CONTROL PLANE
#-------------------------------------------------------------------------------
upgrade_control_plane() {
    local VERSION="$1"
    local NODE_NAME=$(hostname)

    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  UPGRADING FIRST CONTROL PLANE TO v${VERSION}       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Step 1: Upgrade kubeadm
    echo -e "${YELLOW}[1/6] Upgrading kubeadm to ${VERSION}...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-mark unhold kubeadm
        sudo apt-get update -qq
        sudo apt-get install -y --allow-change-held-packages kubeadm=${VERSION}-*
        sudo apt-mark hold kubeadm
    elif command -v yum &> /dev/null; then
        sudo yum install -y kubeadm-${VERSION} --disableexcludes=kubernetes
    fi
    echo -e "${GREEN}  ✅ kubeadm upgraded: $(kubeadm version -o short)${NC}"
    echo ""

    # Step 2: Verify upgrade plan
    echo -e "${YELLOW}[2/6] Verifying upgrade plan...${NC}"
    sudo kubeadm upgrade plan
    echo ""

    # Step 3: Apply upgrade
    echo -e "${YELLOW}[3/6] Applying upgrade to v${VERSION}...${NC}"
    sudo kubeadm upgrade apply v${VERSION} --yes
    echo -e "${GREEN}  ✅ Control plane upgraded${NC}"
    echo ""

    # Step 4: Drain node
    echo -e "${YELLOW}[4/6] Draining node ${NODE_NAME}...${NC}"
    kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data
    echo -e "${GREEN}  ✅ Node drained${NC}"
    echo ""

    # Step 5: Upgrade kubelet and kubectl
    echo -e "${YELLOW}[5/6] Upgrading kubelet and kubectl...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-mark unhold kubelet kubectl
        sudo apt-get install -y --allow-change-held-packages \
            kubelet=${VERSION}-* kubectl=${VERSION}-*
        sudo apt-mark hold kubelet kubectl
    elif command -v yum &> /dev/null; then
        sudo yum install -y kubelet-${VERSION} kubectl-${VERSION} --disableexcludes=kubernetes
    fi
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    echo -e "${GREEN}  ✅ kubelet and kubectl upgraded${NC}"
    echo ""

    # Step 6: Uncordon
    echo -e "${YELLOW}[6/6] Uncordoning node...${NC}"
    kubectl uncordon "$NODE_NAME"
    echo -e "${GREEN}  ✅ Node ${NODE_NAME} is schedulable again${NC}"
    echo ""

    echo -e "${GREEN}✅ First control plane upgrade complete!${NC}"
    kubectl get nodes
}

#-------------------------------------------------------------------------------
# UPGRADE ADDITIONAL CONTROL PLANE
#-------------------------------------------------------------------------------
upgrade_additional_cp() {
    local VERSION="$1"
    local NODE_NAME=$(hostname)

    echo -e "${CYAN}Upgrading additional control plane node: ${NODE_NAME}${NC}"
    echo ""

    # Upgrade kubeadm
    echo -e "${YELLOW}[1/4] Upgrading kubeadm...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-mark unhold kubeadm
        sudo apt-get update -qq
        sudo apt-get install -y --allow-change-held-packages kubeadm=${VERSION}-*
        sudo apt-mark hold kubeadm
    fi

    # Apply node upgrade (not 'upgrade apply', just 'upgrade node')
    echo -e "${YELLOW}[2/4] Applying node upgrade...${NC}"
    sudo kubeadm upgrade node

    # Drain
    echo -e "${YELLOW}[3/4] Draining and upgrading kubelet/kubectl...${NC}"
    kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data
    if command -v apt-get &> /dev/null; then
        sudo apt-mark unhold kubelet kubectl
        sudo apt-get install -y --allow-change-held-packages \
            kubelet=${VERSION}-* kubectl=${VERSION}-*
        sudo apt-mark hold kubelet kubectl
    fi
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet

    # Uncordon
    echo -e "${YELLOW}[4/4] Uncordoning...${NC}"
    kubectl uncordon "$NODE_NAME"
    echo -e "${GREEN}✅ Additional control plane upgraded${NC}"
}

#-------------------------------------------------------------------------------
# UPGRADE WORKER NODE
#-------------------------------------------------------------------------------
upgrade_worker() {
    local NODE_NAME="$1"
    local VERSION="$2"

    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  UPGRADING WORKER NODE: ${NODE_NAME}               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}Run the following commands ON the worker node (${NODE_NAME}):${NC}"
    echo ""
    cat << EOF
# --- Execute on worker node ${NODE_NAME} ---

# Step 1: Drain the worker (run from control plane)
kubectl drain ${NODE_NAME} --ignore-daemonsets --delete-emptydir-data

# Step 2: Upgrade kubeadm (on worker node)
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y --allow-change-held-packages kubeadm=${VERSION}-*
sudo apt-mark hold kubeadm

# Step 3: Apply node config upgrade
sudo kubeadm upgrade node

# Step 4: Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y --allow-change-held-packages kubelet=${VERSION}-* kubectl=${VERSION}-*
sudo apt-mark hold kubelet kubectl

# Step 5: Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Step 6: Uncordon (from control plane)
kubectl uncordon ${NODE_NAME}
EOF
}

#-------------------------------------------------------------------------------
# VERIFY
#-------------------------------------------------------------------------------
do_verify() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     CLUSTER VERIFICATION                         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}Node Status:${NC}"
    kubectl get nodes -o wide
    echo ""

    echo -e "${YELLOW}System Pods:${NC}"
    kubectl get pods -n kube-system
    echo ""

    echo -e "${YELLOW}API Server Version:${NC}"
    kubectl version --short 2>/dev/null || kubectl version
    echo ""

    echo -e "${GREEN}✅ Verification complete${NC}"
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
case "${1:-help}" in
    plan)
        do_plan
        ;;
    upgrade-cp)
        [ -z "${2:-}" ] && echo "Usage: $0 upgrade-cp <version>" && exit 1
        upgrade_control_plane "$2"
        ;;
    upgrade-cp2)
        [ -z "${2:-}" ] && echo "Usage: $0 upgrade-cp2 <version>" && exit 1
        upgrade_additional_cp "$2"
        ;;
    upgrade-worker)
        [ -z "${2:-}" ] || [ -z "${3:-}" ] && echo "Usage: $0 upgrade-worker <node-name> <version>" && exit 1
        upgrade_worker "$2" "$3"
        ;;
    verify)
        do_verify
        ;;
    *)
        echo "Kubernetes Cluster Upgrade Script (kubeadm)"
        echo ""
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  plan                              Show available upgrades"
        echo "  upgrade-cp <version>              Upgrade first control plane"
        echo "  upgrade-cp2 <version>             Upgrade additional control planes"
        echo "  upgrade-worker <node> <version>   Upgrade worker node"
        echo "  verify                            Verify cluster state"
        echo ""
        echo "⚠️  IMPORTANT: Never skip minor versions!"
        echo "   1.30 → 1.31 ✅  |  1.30 → 1.32 ❌"
        ;;
esac


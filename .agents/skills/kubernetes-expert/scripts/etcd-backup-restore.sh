#!/bin/bash
#===============================================================================
# etcd Backup and Restore Script
# For CKA exam preparation and production use
#
# Usage:
#   ./etcd-backup-restore.sh backup [output-path]
#   ./etcd-backup-restore.sh restore [snapshot-path] [data-dir]
#   ./etcd-backup-restore.sh verify [snapshot-path]
#   ./etcd-backup-restore.sh health
#===============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default etcd TLS certificate paths (kubeadm cluster)
ETCDCTL_API=3
ENDPOINT="${ETCD_ENDPOINT:-https://127.0.0.1:2379}"
CACERT="${ETCD_CACERT:-/etc/kubernetes/pki/etcd/ca.crt}"
CERT="${ETCD_CERT:-/etc/kubernetes/pki/etcd/server.crt}"
KEY="${ETCD_KEY:-/etc/kubernetes/pki/etcd/server.key}"

# Detect certificate paths from etcd pod manifest if defaults don't exist
detect_certs() {
    if [ ! -f "$CACERT" ] && [ -f /etc/kubernetes/manifests/etcd.yaml ]; then
        echo -e "${YELLOW}Detecting certificates from etcd manifest...${NC}"
        CACERT=$(grep -A1 '\-\-trusted-ca-file' /etc/kubernetes/manifests/etcd.yaml | tail -1 | tr -d ' ' | sed 's/--trusted-ca-file=//')
        CERT=$(grep -A1 '\-\-cert-file' /etc/kubernetes/manifests/etcd.yaml | tail -1 | tr -d ' ' | sed 's/--cert-file=//')
        KEY=$(grep -A1 '\-\-key-file' /etc/kubernetes/manifests/etcd.yaml | tail -1 | tr -d ' ' | sed 's/--key-file=//')
        ENDPOINT=$(grep -A1 '\-\-listen-client-urls' /etc/kubernetes/manifests/etcd.yaml | tail -1 | tr -d ' ' | sed 's/--listen-client-urls=//' | cut -d',' -f1)
        echo -e "  CACERT:   $CACERT"
        echo -e "  CERT:     $CERT"
        echo -e "  KEY:      $KEY"
        echo -e "  ENDPOINT: $ENDPOINT"
    fi
}

etcd_cmd() {
    etcdctl \
        --endpoints="$ENDPOINT" \
        --cacert="$CACERT" \
        --cert="$CERT" \
        --key="$KEY" \
        "$@"
}

#-------------------------------------------------------------------------------
# BACKUP
#-------------------------------------------------------------------------------
do_backup() {
    local output="${1:-/opt/etcd-backup-$(date +%Y%m%d-%H%M%S).db}"

    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       etcd BACKUP                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    # Step 1: Verify connectivity
    echo -e "${YELLOW}[1/3] Checking etcd health...${NC}"
    if etcd_cmd endpoint health; then
        echo -e "${GREEN}  ✅ etcd is healthy${NC}"
    else
        echo -e "${RED}  ❌ etcd is not healthy. Check certificates and endpoint.${NC}"
        exit 1
    fi
    echo ""

    # Step 2: Create snapshot
    echo -e "${YELLOW}[2/3] Creating snapshot at: ${output}${NC}"
    etcd_cmd snapshot save "$output"
    echo -e "${GREEN}  ✅ Snapshot saved${NC}"
    echo ""

    # Step 3: Verify snapshot
    echo -e "${YELLOW}[3/3] Verifying snapshot integrity...${NC}"
    etcdctl -w table snapshot status "$output"
    echo ""
    echo -e "${GREEN}✅ Backup complete: ${output}${NC}"
    echo -e "${YELLOW}  File size: $(du -h "$output" | cut -f1)${NC}"
}

#-------------------------------------------------------------------------------
# RESTORE
#-------------------------------------------------------------------------------
do_restore() {
    local snapshot="${1:-/opt/etcd-backup.db}"
    local data_dir="${2:-/var/lib/etcd}"

    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       etcd RESTORE                       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -f "$snapshot" ]; then
        echo -e "${RED}❌ Snapshot file not found: ${snapshot}${NC}"
        exit 1
    fi

    echo -e "${RED}⚠️  WARNING: This will restore etcd from snapshot!${NC}"
    echo -e "${RED}   Data directory: ${data_dir}${NC}"
    echo ""
    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi

    # Step 1: Stop control plane (if running as static pods)
    echo ""
    echo -e "${YELLOW}[1/5] Stopping control plane static pods...${NC}"
    if [ -d /etc/kubernetes/manifests ]; then
        mkdir -p /tmp/k8s-manifests-backup
        mv /etc/kubernetes/manifests/*.yaml /tmp/k8s-manifests-backup/ 2>/dev/null || true
        echo -e "${GREEN}  ✅ Static pod manifests moved to /tmp/k8s-manifests-backup/${NC}"
        sleep 5
    else
        echo -e "${YELLOW}  ⚠️  No static pods directory found, skipping...${NC}"
    fi

    # Step 2: Clear existing data directory
    echo -e "${YELLOW}[2/5] Clearing existing data directory...${NC}"
    if [ -d "$data_dir" ]; then
        rm -rf "${data_dir}.bak" 2>/dev/null || true
        mv "$data_dir" "${data_dir}.bak"
        echo -e "${GREEN}  ✅ Old data backed up to ${data_dir}.bak${NC}"
    fi

    # Step 3: Restore snapshot
    echo -e "${YELLOW}[3/5] Restoring snapshot...${NC}"
    ETCDCTL_API=3 etcdctl snapshot restore "$snapshot" \
        --data-dir="$data_dir"
    echo -e "${GREEN}  ✅ Snapshot restored to ${data_dir}${NC}"

    # Step 4: Fix permissions
    echo -e "${YELLOW}[4/5] Fixing data directory permissions...${NC}"
    chown -R etcd:etcd "$data_dir" 2>/dev/null || true
    echo -e "${GREEN}  ✅ Permissions set${NC}"

    # Step 5: Restore control plane manifests
    echo -e "${YELLOW}[5/5] Restoring control plane static pods...${NC}"
    if [ -d /tmp/k8s-manifests-backup ]; then
        mv /tmp/k8s-manifests-backup/*.yaml /etc/kubernetes/manifests/ 2>/dev/null || true
        echo -e "${GREEN}  ✅ Static pod manifests restored${NC}"
    fi

    # Restart kubelet
    echo ""
    echo -e "${YELLOW}Restarting kubelet...${NC}"
    systemctl daemon-reload
    systemctl restart kubelet
    echo -e "${GREEN}  ✅ kubelet restarted${NC}"

    echo ""
    echo -e "${GREEN}✅ Restore complete! Wait 30-60 seconds for control plane to stabilize.${NC}"
    echo -e "${YELLOW}   Then verify with: kubectl get nodes${NC}"
}

#-------------------------------------------------------------------------------
# VERIFY
#-------------------------------------------------------------------------------
do_verify() {
    local snapshot="${1:-/opt/etcd-backup.db}"
    echo -e "${CYAN}Verifying snapshot: ${snapshot}${NC}"
    if [ ! -f "$snapshot" ]; then
        echo -e "${RED}❌ File not found${NC}"
        exit 1
    fi
    etcdctl -w table snapshot status "$snapshot"
    echo -e "${GREEN}✅ Snapshot is valid${NC}"
}

#-------------------------------------------------------------------------------
# HEALTH CHECK
#-------------------------------------------------------------------------------
do_health() {
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       etcd HEALTH CHECK                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Endpoint Health:${NC}"
    etcd_cmd endpoint health
    echo ""
    echo -e "${YELLOW}Endpoint Status:${NC}"
    etcd_cmd -w table endpoint status
    echo ""
    echo -e "${YELLOW}Member List:${NC}"
    etcd_cmd -w table member list
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
detect_certs

case "${1:-help}" in
    backup)
        do_backup "${2:-}"
        ;;
    restore)
        do_restore "${2:-}" "${3:-}"
        ;;
    verify)
        do_verify "${2:-}"
        ;;
    health)
        do_health
        ;;
    *)
        echo "Usage: $0 {backup|restore|verify|health} [args...]"
        echo ""
        echo "Commands:"
        echo "  backup  [output-path]              Take an etcd snapshot"
        echo "  restore [snapshot-path] [data-dir]  Restore from a snapshot"
        echo "  verify  [snapshot-path]             Verify snapshot integrity"
        echo "  health                              Check etcd cluster health"
        echo ""
        echo "Environment Variables:"
        echo "  ETCD_ENDPOINT  (default: https://127.0.0.1:2379)"
        echo "  ETCD_CACERT    (default: /etc/kubernetes/pki/etcd/ca.crt)"
        echo "  ETCD_CERT      (default: /etc/kubernetes/pki/etcd/server.crt)"
        echo "  ETCD_KEY       (default: /etc/kubernetes/pki/etcd/server.key)"
        ;;
esac


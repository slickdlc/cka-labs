#!/bin/bash
#===============================================================================
# Network Policy Generator
# Generates common NetworkPolicy YAML patterns for Kubernetes
#
# Usage:
#   ./network-policy-generator.sh deny-all <namespace>
#   ./network-policy-generator.sh allow-dns <namespace>
#   ./network-policy-generator.sh allow-ingress <namespace> <target-label> <source-label> <port>
#   ./network-policy-generator.sh allow-egress <namespace> <source-label> <cidr> <port>
#   ./network-policy-generator.sh allow-namespace <namespace> <target-label> <source-namespace> <port>
#   ./network-policy-generator.sh web-app <namespace>
#===============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# DENY ALL (Ingress + Egress)
#-------------------------------------------------------------------------------
deny_all() {
    local NS="${1:-default}"
    cat << EOF
# Default Deny All — Namespace: ${NS}
# Blocks ALL ingress and egress traffic for all pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ${NS}
spec:
  podSelector: {}          # Applies to ALL pods in namespace
  policyTypes:
  - Ingress
  - Egress
  # Empty rules = deny everything
EOF
}

#-------------------------------------------------------------------------------
# ALLOW DNS (Required after deny-all egress)
#-------------------------------------------------------------------------------
allow_dns() {
    local NS="${1:-default}"
    cat << EOF
# Allow DNS Egress — Namespace: ${NS}
# Allows pods to resolve DNS via kube-dns (port 53)
# ⚠️ CRITICAL: Apply this alongside default-deny-all or apps break!
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: ${NS}
spec:
  podSelector: {}          # All pods in namespace
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
}

#-------------------------------------------------------------------------------
# ALLOW INGRESS from specific pod label
#-------------------------------------------------------------------------------
allow_ingress() {
    local NS="${1:-default}"
    local TARGET="${2:-app=backend}"
    local SOURCE="${3:-app=frontend}"
    local PORT="${4:-8080}"

    local TARGET_KEY="${TARGET%%=*}"
    local TARGET_VAL="${TARGET##*=}"
    local SOURCE_KEY="${SOURCE%%=*}"
    local SOURCE_VAL="${SOURCE##*=}"

    cat << EOF
# Allow Ingress: ${SOURCE} → ${TARGET} on port ${PORT}
# Namespace: ${NS}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-${SOURCE_VAL}-to-${TARGET_VAL}
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      ${TARGET_KEY}: ${TARGET_VAL}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          ${SOURCE_KEY}: ${SOURCE_VAL}
    ports:
    - protocol: TCP
      port: ${PORT}
EOF
}

#-------------------------------------------------------------------------------
# ALLOW EGRESS to CIDR
#-------------------------------------------------------------------------------
allow_egress() {
    local NS="${1:-default}"
    local SOURCE="${2:-app=backend}"
    local CIDR="${3:-10.0.0.0/8}"
    local PORT="${4:-443}"

    local SOURCE_KEY="${SOURCE%%=*}"
    local SOURCE_VAL="${SOURCE##*=}"

    cat << EOF
# Allow Egress: ${SOURCE} → ${CIDR}:${PORT}
# Namespace: ${NS}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-${SOURCE_VAL}-egress-${PORT}
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      ${SOURCE_KEY}: ${SOURCE_VAL}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: ${CIDR}
    ports:
    - protocol: TCP
      port: ${PORT}
EOF
}

#-------------------------------------------------------------------------------
# ALLOW INGRESS from another namespace
#-------------------------------------------------------------------------------
allow_namespace() {
    local NS="${1:-default}"
    local TARGET="${2:-app=backend}"
    local SRC_NS="${3:-monitoring}"
    local PORT="${4:-9090}"

    local TARGET_KEY="${TARGET%%=*}"
    local TARGET_VAL="${TARGET##*=}"

    cat << EOF
# Allow Ingress from namespace ${SRC_NS} → ${TARGET} on port ${PORT}
# Namespace: ${NS}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-${SRC_NS}
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      ${TARGET_KEY}: ${TARGET_VAL}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${SRC_NS}
    ports:
    - protocol: TCP
      port: ${PORT}
EOF
}

#-------------------------------------------------------------------------------
# COMPLETE WEB APP pattern (deny-all + DNS + frontend→backend + ingress)
#-------------------------------------------------------------------------------
web_app() {
    local NS="${1:-default}"

    echo -e "${CYAN}# ============================================${NC}"
    echo -e "${CYAN}# Complete Web App NetworkPolicy Set${NC}"
    echo -e "${CYAN}# Namespace: ${NS}${NC}"
    echo -e "${CYAN}# ============================================${NC}"
    echo ""

    deny_all "$NS"
    echo "---"
    allow_dns "$NS"
    echo "---"
    cat << EOF
# Allow external ingress to frontend pods (port 80)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-ingress
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 80
---
# Allow frontend → backend (port 8080)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
---
# Allow backend → database (port 5432)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-db
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 5432
---
# Allow frontend egress to backend only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 8080
  # Also allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
case "${1:-help}" in
    deny-all)
        deny_all "${2:-default}"
        ;;
    allow-dns)
        allow_dns "${2:-default}"
        ;;
    allow-ingress)
        allow_ingress "${2:-default}" "${3:-app=backend}" "${4:-app=frontend}" "${5:-8080}"
        ;;
    allow-egress)
        allow_egress "${2:-default}" "${3:-app=backend}" "${4:-10.0.0.0/8}" "${5:-443}"
        ;;
    allow-namespace)
        allow_namespace "${2:-default}" "${3:-app=backend}" "${4:-monitoring}" "${5:-9090}"
        ;;
    web-app)
        web_app "${2:-default}"
        ;;
    *)
        echo "Network Policy Generator"
        echo ""
        echo "Usage: $0 <pattern> [args...]"
        echo ""
        echo "Patterns:"
        echo "  deny-all <ns>                                   Deny all ingress+egress"
        echo "  allow-dns <ns>                                  Allow DNS resolution"
        echo "  allow-ingress <ns> <target> <source> <port>     Allow pod-to-pod ingress"
        echo "  allow-egress <ns> <source> <cidr> <port>        Allow egress to CIDR"
        echo "  allow-namespace <ns> <target> <src-ns> <port>   Allow cross-namespace"
        echo "  web-app <ns>                                    Complete 3-tier web app"
        echo ""
        echo "Examples:"
        echo "  $0 deny-all production"
        echo "  $0 allow-dns production"
        echo "  $0 allow-ingress production app=api app=web 8080"
        echo "  $0 web-app my-app > network-policies.yaml"
        ;;
esac


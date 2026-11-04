#!/bin/bash
#===============================================================================
# Kubernetes Exam Environment Bootstrap Script
# Run this FIRST when your exam terminal opens!
#
# Usage: source exam-setup.sh
#===============================================================================

set -e

echo "🚀 Setting up Kubernetes Exam Environment..."

#-------------------------------------------------------------------------------
# 1. BASH ALIASES & SHORTCUTS
#-------------------------------------------------------------------------------
cat >> ~/.bashrc << 'ALIASES'

# ============================================
# Kubernetes Exam Aliases
# ============================================

# Core shortcut
alias k=kubectl
alias ka="kubectl apply -f"
alias kaf="kubectl apply -f"
alias kr="kubectl replace --force -f"

# Get resources
alias kgp="kubectl get pods"
alias kgpa="kubectl get pods -A"
alias kgpw="kubectl get pods -o wide"
alias kgpaw="kubectl get pods -A -o wide"
alias kgd="kubectl get deployments"
alias kgs="kubectl get services"
alias kgn="kubectl get nodes"
alias kgno="kubectl get nodes -o wide"
alias kga="kubectl get all"
alias kgaa="kubectl get all -A"
alias kgns="kubectl get namespaces"
alias kgcm="kubectl get configmaps"
alias kgsec="kubectl get secrets"
alias kgpv="kubectl get pv"
alias kgpvc="kubectl get pvc"
alias kgsc="kubectl get storageclass"
alias kgnp="kubectl get networkpolicies"
alias kgep="kubectl get endpoints"
alias kging="kubectl get ingress"
alias kgsa="kubectl get serviceaccounts"
alias kgr="kubectl get roles"
alias kgrb="kubectl get rolebindings"
alias kgcr="kubectl get clusterroles"
alias kgcrb="kubectl get clusterrolebindings"
alias kgds="kubectl get daemonsets"
alias kgss="kubectl get statefulsets"
alias kgj="kubectl get jobs"
alias kgcj="kubectl get cronjobs"
alias kgev="kubectl get events --sort-by='.lastTimestamp'"

# Describe
alias kdp="kubectl describe pod"
alias kdd="kubectl describe deployment"
alias kds="kubectl describe service"
alias kdn="kubectl describe node"

# Logs
alias kl="kubectl logs"
alias klf="kubectl logs -f"

# Delete
alias kdel="kubectl delete"
alias kdelp="kubectl delete pod"

# Context & Namespace
alias kn='kubectl config set-context --current --namespace'
alias kctx='kubectl config get-contexts'
alias kuc='kubectl config use-context'
alias kcv='kubectl config view --minify'

# Quick DRY-RUN and FORCE variables
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"

ALIASES

#-------------------------------------------------------------------------------
# 2. BASH COMPLETION
#-------------------------------------------------------------------------------
cat >> ~/.bashrc << 'COMPLETION'

# Kubectl autocompletion
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
COMPLETION

#-------------------------------------------------------------------------------
# 3. VIM CONFIGURATION (Critical for YAML editing)
#-------------------------------------------------------------------------------
cat > ~/.vimrc << 'VIMRC'
" Kubernetes Exam VIM Configuration
set nu                  " Show line numbers
set tabstop=2           " Tab = 2 spaces
set shiftwidth=2        " Indent = 2 spaces
set expandtab           " Tabs → spaces (CRITICAL for YAML)
set autoindent          " Auto-indent new lines
set smartindent         " Smart indentation
set cursorline          " Highlight current line
set hlsearch            " Highlight search results
set incsearch           " Incremental search
set paste               " Prevents auto-indent when pasting
syntax on               " Syntax highlighting
VIMRC

#-------------------------------------------------------------------------------
# 4. TMUX CONFIG (if available)
#-------------------------------------------------------------------------------
if command -v tmux &> /dev/null; then
    cat > ~/.tmux.conf << 'TMUX'
set -g mouse on
set -g history-limit 10000
TMUX
fi

#-------------------------------------------------------------------------------
# 5. USEFUL FUNCTIONS
#-------------------------------------------------------------------------------
cat >> ~/.bashrc << 'FUNCTIONS'

# Quick pod YAML generator
krun() {
    kubectl run "$1" --image="$2" --dry-run=client -o yaml > "${1}.yaml"
    echo "Generated ${1}.yaml"
}

# Quick deployment YAML generator
kdep() {
    kubectl create deployment "$1" --image="$2" --replicas="${3:-1}" --dry-run=client -o yaml > "${1}-deploy.yaml"
    echo "Generated ${1}-deploy.yaml"
}

# Quick service YAML generator
ksvc() {
    kubectl expose "$1" "$2" --port="$3" --target-port="${4:-$3}" --dry-run=client -o yaml > "${2}-svc.yaml"
    echo "Generated ${2}-svc.yaml"
}

# Check current context and namespace
kinfo() {
    echo "Context:   $(kubectl config current-context)"
    echo "Namespace: $(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || echo 'default')"
    echo "Cluster:   $(kubectl config view --minify --output 'jsonpath={.clusters[0].cluster.server}')"
}

# Quick pod debug
kdebug() {
    kubectl run debug-pod --rm -it --image=busybox:1.36 --restart=Never -- sh
}

# Get all images in cluster
kimages() {
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'
}

FUNCTIONS

# Reload bashrc
source ~/.bashrc

echo ""
echo "✅ Exam environment ready!"
echo ""
echo "📋 Quick Reference:"
echo "  k           = kubectl"
echo "  kgp         = kubectl get pods"
echo "  kgpa        = kubectl get pods -A"
echo "  kn <ns>     = switch namespace"
echo "  kuc <ctx>   = switch context"
echo "  kinfo       = show current context/namespace"
echo "  \$do         = --dry-run=client -o yaml"
echo "  \$now        = --force --grace-period=0"
echo ""
echo "  Example: k run nginx --image=nginx \$do > pod.yaml"
echo ""


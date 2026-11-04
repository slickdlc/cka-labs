#===============================================================================
# Kubernetes Exam Environment Bootstrap Script - PowerShell Edition
# For Windows/WSL development environments
#
# Usage: . .\exam-setup.ps1
#===============================================================================

Write-Host "🚀 Setting up Kubernetes Exam Environment (PowerShell)..." -ForegroundColor Cyan

#-------------------------------------------------------------------------------
# 1. POWERSHELL ALIASES & FUNCTIONS
#-------------------------------------------------------------------------------

# Core aliases
Set-Alias -Name k -Value kubectl -Scope Global
function ka { kubectl apply -f $args }
function kaf { kubectl apply -f $args }

# Get resources
function kgp { kubectl get pods $args }
function kgpa { kubectl get pods -A $args }
function kgpw { kubectl get pods -o wide $args }
function kgpaw { kubectl get pods -A -o wide $args }
function kgd { kubectl get deployments $args }
function kgs { kubectl get services $args }
function kgn { kubectl get nodes $args }
function kgno { kubectl get nodes -o wide $args }
function kga { kubectl get all $args }
function kgaa { kubectl get all -A $args }
function kgns { kubectl get namespaces $args }
function kgcm { kubectl get configmaps $args }
function kgsec { kubectl get secrets $args }
function kgpv { kubectl get pv $args }
function kgpvc { kubectl get pvc $args }
function kgsc { kubectl get storageclass $args }
function kgnp { kubectl get networkpolicies $args }
function kgep { kubectl get endpoints $args }
function kging { kubectl get ingress $args }
function kgsa { kubectl get serviceaccounts $args }
function kgev { kubectl get events --sort-by='.lastTimestamp' $args }
function kgds { kubectl get daemonsets $args }
function kgss { kubectl get statefulsets $args }
function kgj { kubectl get jobs $args }
function kgcj { kubectl get cronjobs $args }

# Describe
function kdp { kubectl describe pod $args }
function kdd { kubectl describe deployment $args }
function kds { kubectl describe service $args }
function kdn { kubectl describe node $args }

# Logs
function kl { kubectl logs $args }
function klf { kubectl logs -f $args }

# Delete
function kdel { kubectl delete $args }
function kdelp { kubectl delete pod $args }

# Context & Namespace
function kn { kubectl config set-context --current --namespace=$args }
function kctx { kubectl config get-contexts }
function kuc { kubectl config use-context $args }
function kcv { kubectl config view --minify }

# Dry-run & force-delete helpers
$Global:do = "--dry-run=client -o yaml"
$Global:now = "--force --grace-period=0"

#-------------------------------------------------------------------------------
# 2. KUBECTL AUTOCOMPLETION FOR POWERSHELL
#-------------------------------------------------------------------------------
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    kubectl completion powershell | Out-String | Invoke-Expression
}

#-------------------------------------------------------------------------------
# 3. USEFUL UTILITY FUNCTIONS
#-------------------------------------------------------------------------------

# Quick pod YAML generator
function krun {
    param([string]$Name, [string]$Image)
    kubectl run $Name --image=$Image --dry-run=client -o yaml | Out-File -Encoding utf8 "$Name.yaml"
    Write-Host "Generated $Name.yaml" -ForegroundColor Green
}

# Quick deployment YAML generator
function kdep {
    param([string]$Name, [string]$Image, [int]$Replicas = 1)
    kubectl create deployment $Name --image=$Image --replicas=$Replicas --dry-run=client -o yaml | Out-File -Encoding utf8 "$Name-deploy.yaml"
    Write-Host "Generated $Name-deploy.yaml" -ForegroundColor Green
}

# Check current context and namespace
function kinfo {
    $ctx = kubectl config current-context
    $ns = kubectl config view --minify --output 'jsonpath={..namespace}' 2>$null
    if (-not $ns) { $ns = "default" }
    $cluster = kubectl config view --minify --output 'jsonpath={.clusters[0].cluster.server}'
    Write-Host "Context:   $ctx" -ForegroundColor Yellow
    Write-Host "Namespace: $ns" -ForegroundColor Yellow
    Write-Host "Cluster:   $cluster" -ForegroundColor Yellow
}

# Quick debug pod
function kdebug {
    kubectl run debug-pod --rm -it --image=busybox:1.36 --restart=Never -- sh
}

# List all images in cluster
function kimages {
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"`t"}{.metadata.name}{"`t"}{range .spec.containers[*]}{.image}{"`n"}{end}{end}'
}

# Check cluster health
function khealth {
    Write-Host "`n=== Nodes ===" -ForegroundColor Cyan
    kubectl get nodes
    Write-Host "`n=== Component Status ===" -ForegroundColor Cyan
    kubectl get --raw='/readyz?verbose' 2>$null
    Write-Host "`n=== System Pods ===" -ForegroundColor Cyan
    kubectl get pods -n kube-system
}

#-------------------------------------------------------------------------------
# 4. DISPLAY HELP
#-------------------------------------------------------------------------------

Write-Host ""
Write-Host "✅ Exam environment ready!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Quick Reference:" -ForegroundColor Yellow
Write-Host "  k           = kubectl"
Write-Host "  kgp         = kubectl get pods"
Write-Host "  kgpa        = kubectl get pods -A"
Write-Host '  kn <ns>     = switch namespace'
Write-Host '  kuc <ctx>   = switch context'
Write-Host "  kinfo       = show current context/namespace"
Write-Host '  $do         = --dry-run=client -o yaml'
Write-Host '  $now        = --force --grace-period=0'
Write-Host ""
Write-Host '  Example: k run nginx --image=nginx $do > pod.yaml'
Write-Host ""


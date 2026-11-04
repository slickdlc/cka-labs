# kubectl Mastery Reference

> Complete command reference optimized for CKA, CKAD, and CKS exam environments.

---

## Exam Environment Speed Setup

### ~/.bashrc Aliases and Variables

```bash
# Core alias
alias k=kubectl
complete -o default -F __start_kubectl k

# Namespace shortcut
alias kn='kubectl config set-context --current --namespace'

# GET shortcuts
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kgns='kubectl get namespaces'
alias kge='kubectl get events --sort-by=.metadata.creationTimestamp'
alias kgpv='kubectl get pv'
alias kgpvc='kubectl get pvc'
alias kgsa='kubectl get sa'
alias kgcm='kubectl get configmaps'
alias kgsec='kubectl get secrets'
alias kgi='kubectl get ingress'
alias kgnp='kubectl get networkpolicy'
alias kgall='kubectl get all'

# DESCRIBE shortcuts
alias kdp='kubectl describe pod'
alias kds='kubectl describe svc'
alias kdd='kubectl describe deployment'
alias kdn='kubectl describe node'

# DELETE shortcuts
alias kdel='kubectl delete'

# LOGS shortcut
alias kl='kubectl logs'
alias klf='kubectl logs -f'

# Environment variables for speed
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'

# Quick YAML generation: k run nginx --image=nginx $do > pod.yaml
# Quick force delete:    k delete pod nginx $now
```

### ~/.vimrc Configuration

```vim
set tabstop=2
set shiftwidth=2
set expandtab
set autoindent
set smartindent
set number
set cursorline
set paste
```

> **Tip:** `set paste` prevents auto-indent issues when pasting YAML. If you need auto-indent while typing, temporarily `:set nopaste`.

### Autocompletion Setup

```bash
# bash completion (usually pre-installed in exam)
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

# Verify it works
k get <TAB><TAB>
```

### tmux Basics (Available in Exam)

```bash
# Split pane horizontally
Ctrl+b "

# Split pane vertically
Ctrl+b %

# Switch between panes
Ctrl+b <arrow-key>

# Scroll mode (to scroll up in output)
Ctrl+b [    # then use arrow keys, q to exit
```

---

## 1. Resource Creation (Imperative Commands)

> **Golden Rule:** Use imperative commands to generate YAML, then modify as needed.  
> Pattern: `kubectl <command> <args> --dry-run=client -o yaml > resource.yaml`

### Pods

```bash
# Run a pod
k run nginx --image=nginx

# Run with labels
k run nginx --image=nginx --labels="app=web,tier=frontend"

# Run with port exposed
k run nginx --image=nginx --port=80

# Run with environment variables
k run nginx --image=nginx --env="DB_HOST=mysql" --env="DB_PORT=3306"

# Run with resource requests/limits
k run nginx --image=nginx --requests="cpu=100m,memory=128Mi" --limits="cpu=200m,memory=256Mi"

# Run with command override
k run busybox --image=busybox --command -- sleep 3600

# Run with arguments (entrypoint stays, args override)
k run busybox --image=busybox -- sleep 3600

# Generate YAML without creating
k run nginx --image=nginx $do > pod.yaml

# Run a temporary interactive pod
k run tmp --image=busybox --rm -it --restart=Never -- sh

# Run a temporary pod for DNS testing
k run tmp --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes

# Run a temporary curl pod
k run tmp --image=curlimages/curl --rm -it --restart=Never -- curl http://svc-name:port
```

### Deployments

```bash
# Create deployment
k create deployment nginx --image=nginx

# With replicas
k create deployment nginx --image=nginx --replicas=3

# With port
k create deployment nginx --image=nginx --port=80

# Generate YAML
k create deployment nginx --image=nginx --replicas=3 $do > deploy.yaml
```

### Services

```bash
# Expose a pod as ClusterIP
k expose pod nginx --port=80 --target-port=80 --name=nginx-svc

# Expose a deployment as ClusterIP
k expose deployment nginx --port=80 --target-port=80

# Expose as NodePort
k expose deployment nginx --port=80 --target-port=80 --type=NodePort

# Create ClusterIP service (without a selector — useful for external services)
k create service clusterip my-svc --tcp=80:80

# Create NodePort with specific port
k create service nodeport my-svc --tcp=80:80 --node-port=30080

# Generate YAML
k expose deployment nginx --port=80 --type=ClusterIP $do > svc.yaml
```

### ConfigMaps

```bash
# From literal values
k create configmap my-config --from-literal=key1=value1 --from-literal=key2=value2

# From a file
k create configmap my-config --from-file=config.txt

# From a file with custom key
k create configmap my-config --from-file=mykey=config.txt

# From a directory
k create configmap my-config --from-file=./config-dir/

# From env file
k create configmap my-config --from-env-file=env.properties

# Generate YAML
k create configmap my-config --from-literal=key1=value1 $do > cm.yaml
```

### Secrets

```bash
# Generic secret from literals
k create secret generic my-secret --from-literal=username=admin --from-literal=password=s3cr3t

# From file
k create secret generic my-secret --from-file=ssh-key=~/.ssh/id_rsa

# Docker registry secret
k create secret docker-registry my-reg-secret \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --docker-email=user@example.com

# TLS secret
k create secret tls my-tls-secret --cert=cert.pem --key=key.pem

# Generate YAML
k create secret generic my-secret --from-literal=pass=s3cr3t $do > secret.yaml
```

### Jobs and CronJobs

```bash
# Create a job
k create job my-job --image=busybox -- echo "Hello"

# Create a job from a cronjob (trigger manual run)
k create job my-job --from=cronjob/my-cronjob

# Create a cronjob
k create cronjob my-cron --image=busybox --schedule="*/5 * * * *" -- echo "Hello"

# Generate YAML
k create job my-job --image=busybox $do -- echo "Hello" > job.yaml
k create cronjob my-cron --image=busybox --schedule="0 * * * *" $do -- echo "Hi" > cron.yaml
```

### RBAC Resources

```bash
# Create Role
k create role pod-reader --verb=get,list,watch --resource=pods

# Create Role with specific resource names
k create role pod-reader --verb=get --resource=pods --resource-name=my-pod

# Create RoleBinding
k create rolebinding pod-reader-binding --role=pod-reader --user=jane

# RoleBinding with ServiceAccount
k create rolebinding pod-reader-binding --role=pod-reader --serviceaccount=default:my-sa

# Create ClusterRole
k create clusterrole node-reader --verb=get,list,watch --resource=nodes

# ClusterRole with non-resource URLs
k create clusterrole monitoring --verb=get --non-resource-url="/healthz" --non-resource-url="/metrics"

# Create ClusterRoleBinding
k create clusterrolebinding node-reader-binding --clusterrole=node-reader --user=jane

# ClusterRoleBinding with group
k create clusterrolebinding admin-binding --clusterrole=cluster-admin --group=admins

# Generate YAML
k create role pod-reader --verb=get,list --resource=pods $do > role.yaml
k create rolebinding binding --role=pod-reader --user=jane $do > rb.yaml
```

### ServiceAccounts

```bash
# Create ServiceAccount
k create serviceaccount my-sa

# Generate YAML
k create serviceaccount my-sa $do > sa.yaml
```

### Namespaces

```bash
# Create namespace
k create namespace my-ns

# or shorthand
k create ns my-ns
```

### Resource Quotas

```bash
# Create quota
k create quota my-quota --hard=pods=10,requests.cpu=4,requests.memory=8Gi,limits.cpu=8,limits.memory=16Gi

# Generate YAML
k create quota my-quota --hard=pods=10,requests.cpu=4 $do > quota.yaml
```

### Ingress

```bash
# Create ingress
k create ingress my-ingress --rule="host.example.com/path=svc-name:80"

# With TLS
k create ingress my-ingress --rule="host.example.com/path=svc-name:80,tls=my-tls-secret"

# Multiple rules
k create ingress my-ingress \
  --rule="foo.com/=foo-svc:80" \
  --rule="bar.com/=bar-svc:80"

# Default backend
k create ingress my-ingress --default-backend=default-svc:80 --rule="host.com/path=svc:80"

# Generate YAML
k create ingress my-ingress --rule="host.com/=svc:80" $do > ingress.yaml
```

---

## 2. Resource Inspection

### kubectl get

```bash
# Basic listing
k get pods
k get pods -A                          # All namespaces
k get pods -n kube-system              # Specific namespace
k get pods --show-labels               # Show labels
k get pods -l app=nginx                # Filter by label
k get pods -l 'app in (nginx,apache)'  # Set-based selector
k get pods -l 'app!=nginx'             # Exclusion
k get pods --field-selector=status.phase=Running  # Field selector
k get pods --field-selector=spec.nodeName=node01  # By node

# Output formats
k get pods -o wide                     # Extra info (node, IP)
k get pods -o yaml                     # Full YAML
k get pods -o json                     # Full JSON
k get pods -o name                     # Just resource names
k get pod nginx -o yaml > pod.yaml     # Export to file

# JSONPath output
k get pods -o jsonpath='{.items[*].metadata.name}'
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

# Custom columns
k get pods -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName'
k get pods -o custom-columns='NAME:.metadata.name,IMAGES:.spec.containers[*].image'

# Sort
k get pods --sort-by=.metadata.creationTimestamp
k get pods --sort-by=.status.startTime
k get pv --sort-by=.spec.capacity.storage

# Watch for changes
k get pods -w
```

### kubectl describe

```bash
# Describe gives human-readable detail including events
k describe pod nginx
k describe node node01
k describe svc my-svc
k describe pvc my-pvc
k describe ingress my-ingress

# Key sections to check in describe output:
# - Events (bottom) — most common source of troubleshooting info
# - Conditions
# - Containers → State, Ready, Restart Count
# - Volumes and Mounts
# - Node-Selectors and Tolerations
```

### kubectl explain

```bash
# Top-level fields
k explain pod
k explain pod.spec
k explain pod.spec.containers
k explain pod.spec.containers.livenessProbe

# Recursive (show all nested fields)
k explain pod.spec --recursive

# Specific API version
k explain pod --api-version=v1

# Common lookups during exams
k explain pod.spec.volumes
k explain pod.spec.containers.volumeMounts
k explain pod.spec.securityContext
k explain pod.spec.containers.securityContext
k explain deployment.spec.strategy
k explain ingress.spec.rules
k explain networkpolicy.spec
k explain pv.spec.persistentVolumeReclaimPolicy
```

### kubectl api-resources and api-versions

```bash
# List all resource types
k api-resources

# Filter by namespaced resources
k api-resources --namespaced=true
k api-resources --namespaced=false

# Filter by API group
k api-resources --api-group=apps
k api-resources --api-group=rbac.authorization.k8s.io

# Short names
k api-resources --sort-by=name | grep -i "short"
# Common short names: po, svc, deploy, ds, rs, sts, cm, sa, ns, pv, pvc, no, ing, netpol, ep

# List available API versions
k api-versions
```

---

## 3. Resource Modification

### kubectl edit

```bash
# Opens resource in $KUBE_EDITOR or $EDITOR (defaults to vi)
k edit pod nginx
k edit deployment nginx
k edit svc my-svc

# Use a different editor
KUBE_EDITOR=nano k edit deployment nginx
```

### kubectl patch

```bash
# Strategic merge patch (default)
k patch deployment nginx -p '{"spec":{"replicas":5}}'

# JSON merge patch
k patch deployment nginx --type=merge -p '{"spec":{"replicas":5}}'

# JSON patch (add, remove, replace operations)
k patch deployment nginx --type=json -p '[{"op":"replace","path":"/spec/replicas","value":5}]'

# Patch a node (e.g., add label)
k patch node node01 -p '{"metadata":{"labels":{"disk":"ssd"}}}'

# Remove a field with JSON patch
k patch deployment nginx --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/resources/limits"}]'
```

### kubectl label

```bash
# Add label
k label pod nginx app=web

# Overwrite existing label
k label pod nginx app=api --overwrite

# Remove label (trailing dash)
k label pod nginx app-

# Label multiple resources
k label pods --all tier=frontend

# Label by selector
k label pods -l app=nginx tier=frontend

# Label a node (for nodeSelector / nodeAffinity)
k label node node01 disk=ssd
```

### kubectl annotate

```bash
# Add annotation
k annotate pod nginx description="My web server"

# Overwrite
k annotate pod nginx description="Updated" --overwrite

# Remove annotation
k annotate pod nginx description-
```

### kubectl scale

```bash
# Scale deployment
k scale deployment nginx --replicas=5

# Scale by selector
k scale deployment -l app=web --replicas=3

# Scale replicaset
k scale rs my-rs --replicas=3

# Scale statefulset
k scale sts my-sts --replicas=3
```

### kubectl autoscale

```bash
# Create HPA
k autoscale deployment nginx --min=2 --max=10 --cpu-percent=80

# Generate YAML
k autoscale deployment nginx --min=2 --max=10 --cpu-percent=80 $do > hpa.yaml
```

### kubectl set

```bash
# Update container image
k set image deployment/nginx nginx=nginx:1.25
k set image deployment/nginx nginx=nginx:1.25 --record  # deprecated but may appear in exams

# Update multiple containers
k set image deployment/my-app app=app:v2 sidecar=sidecar:v2

# Set environment variables
k set env deployment/nginx DB_HOST=mysql DB_PORT=3306

# Set env from configmap
k set env deployment/nginx --from=configmap/my-config

# Set env from secret
k set env deployment/nginx --from=secret/my-secret

# List environment variables
k set env deployment/nginx --list

# Remove an env var
k set env deployment/nginx DB_HOST-

# Set resource requests/limits
k set resources deployment/nginx --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi

# Set serviceaccount
k set serviceaccount deployment/nginx my-sa
k set sa deployment/nginx my-sa   # shorthand
```

---

## 4. Resource Deletion

```bash
# Delete by name
k delete pod nginx
k delete deployment nginx

# Force delete (fast, skip graceful shutdown — essential in exams)
k delete pod nginx $now
# Expands to: kubectl delete pod nginx --force --grace-period=0

# Delete by label
k delete pods -l app=nginx

# Delete all pods in namespace
k delete pods --all -n my-ns

# Delete all resources in namespace
k delete all --all -n my-ns

# Delete from file
k delete -f pod.yaml

# Delete namespace (deletes everything inside)
k delete ns my-ns
```

---

## 5. Debugging

### kubectl logs

```bash
# Pod logs
k logs nginx

# Follow (stream) logs
k logs nginx -f

# Specific container in multi-container pod
k logs nginx -c sidecar

# Previous container (after crash/restart)
k logs nginx --previous
k logs nginx -c main --previous

# Time-based filtering
k logs nginx --since=1h
k logs nginx --since=5m
k logs nginx --since-time="2024-01-01T00:00:00Z"

# Tail last N lines
k logs nginx --tail=100

# All containers in pod
k logs nginx --all-containers=true

# Logs by label selector
k logs -l app=nginx

# Logs by label with follow
k logs -l app=nginx -f --max-log-requests=10
```

### kubectl exec

```bash
# Execute command in pod
k exec nginx -- ls /usr/share/nginx/html

# Interactive shell
k exec -it nginx -- /bin/bash
k exec -it nginx -- /bin/sh     # if bash not available

# Specific container
k exec -it nginx -c sidecar -- /bin/sh

# Useful debugging commands inside a pod
k exec -it nginx -- cat /etc/resolv.conf
k exec -it nginx -- env
k exec -it nginx -- mount
k exec -it nginx -- wget -O- http://localhost:80
k exec -it nginx -- printenv
k exec -it nginx -- id                   # check user/group
k exec -it nginx -- cat /proc/1/status   # check process
```

### kubectl debug

```bash
# Create ephemeral debug container in a running pod
k debug -it pod/nginx --image=busybox --target=nginx

# Debug with a copy of the pod (different image)
k debug pod/nginx -it --copy-to=debug-pod --image=busybox

# Debug a node
k debug node/node01 -it --image=busybox
# This creates a pod with the node's filesystem mounted at /host
# chroot /host  — to access node's tools and filesystem

# Debug with specific container name
k debug -it pod/nginx --image=busybox --container=debugger
```

### kubectl port-forward

```bash
# Forward pod port to local
k port-forward pod/nginx 8080:80

# Forward service port
k port-forward svc/nginx-svc 8080:80

# Forward deployment port
k port-forward deployment/nginx 8080:80

# Listen on all interfaces
k port-forward --address 0.0.0.0 pod/nginx 8080:80
```

### kubectl cp

```bash
# Copy from local to pod
k cp ./local-file.txt nginx:/tmp/file.txt

# Copy from pod to local
k cp nginx:/var/log/nginx/error.log ./error.log

# Specific container
k cp nginx:/tmp/file.txt ./file.txt -c sidecar

# Copy with namespace
k cp my-ns/nginx:/tmp/file.txt ./file.txt
```

### kubectl attach

```bash
# Attach to a running process (stdin/stdout)
k attach nginx -it

# Specific container
k attach nginx -c main -it
```

### kubectl top

```bash
# Node resource usage (requires metrics-server)
k top nodes

# Pod resource usage
k top pods
k top pods -A                           # All namespaces
k top pods --sort-by=cpu
k top pods --sort-by=memory
k top pods -l app=nginx

# Container-level usage
k top pods --containers
```

---

## 6. Cluster Management

### kubectl config (Context Management)

```bash
# View config
k config view
k config view --minify              # Only current context

# List contexts
k config get-contexts

# Current context
k config current-context

# Switch context
k config use-context my-cluster

# Set default namespace for context
k config set-context --current --namespace=my-ns

# Create a new context
k config set-context my-context --cluster=my-cluster --user=my-user --namespace=my-ns

# Delete context
k config delete-context my-context

# Set credentials
k config set-credentials my-user --client-certificate=cert.pem --client-key=key.pem
```

### Node Management

```bash
# Drain node (evict pods, mark unschedulable)
k drain node01 --ignore-daemonsets --delete-emptydir-data

# Mark node unschedulable (no new pods, existing stay)
k cordon node01

# Mark node schedulable again
k uncordon node01

# Taint a node
k taint nodes node01 key=value:NoSchedule

# Remove a taint (trailing dash)
k taint nodes node01 key=value:NoSchedule-
k taint nodes node01 key-    # Remove all taints with that key

# Common taint effects: NoSchedule, PreferNoSchedule, NoExecute
```

---

## 7. Advanced Operations

### kubectl rollout

```bash
# Check rollout status
k rollout status deployment/nginx

# View rollout history
k rollout history deployment/nginx

# View specific revision
k rollout history deployment/nginx --revision=2

# Undo last rollout
k rollout undo deployment/nginx

# Undo to specific revision
k rollout undo deployment/nginx --to-revision=2

# Restart (rolling restart — triggers new rollout)
k rollout restart deployment/nginx

# Pause rollout (for canary-style)
k rollout pause deployment/nginx

# Resume rollout
k rollout resume deployment/nginx
```

### kubectl auth

```bash
# Check if you can do something
k auth can-i create pods
k auth can-i delete deployments --namespace=production

# Check as another user
k auth can-i create pods --as=jane
k auth can-i get secrets --as=system:serviceaccount:default:my-sa

# Check as a group
k auth can-i create pods --as-group=developers

# List all permissions
k auth can-i --list
k auth can-i --list --as=jane
k auth can-i --list --namespace=kube-system
```

### kubectl diff, apply, replace

```bash
# Show diff before applying
k diff -f deployment.yaml

# Apply (declarative — create or update)
k apply -f deployment.yaml
k apply -f ./manifests/          # Apply all files in directory
k apply -f https://url/to/manifest.yaml
k apply -k ./kustomize-dir/     # Kustomize

# Replace (delete and recreate — use when apply fails due to immutable fields)
k replace -f deployment.yaml
k replace --force -f pod.yaml   # Force replace (delete + create)

# Create if not exists, apply if exists
k apply -f resource.yaml
```

### kubectl wait

```bash
# Wait for pod to be ready
k wait --for=condition=Ready pod/nginx --timeout=60s

# Wait for all pods with label
k wait --for=condition=Ready pods -l app=nginx --timeout=120s

# Wait for deletion
k wait --for=delete pod/nginx --timeout=60s

# Wait for job completion
k wait --for=condition=Complete job/my-job --timeout=300s
```

---

## 8. JSONPath Mastery

> JSONPath is critical for exams. Practice these patterns until they're automatic.

### Syntax Reference

| Expression | Meaning |
|---|---|
| `$` | Root object |
| `.field` | Child field |
| `[n]` | Array index |
| `[*]` | All elements |
| `[?(@.field==value)]` | Filter |
| `{range .items[*]}...{end}` | Iteration |
| `{"\n"}`, `{"\t"}` | Formatting |

### Common Patterns

```bash
# Get all pod names
k get pods -o jsonpath='{.items[*].metadata.name}'

# Get all pod names, one per line
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

# Pod name and status
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

# Get all node internal IPs
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'

# Get node names and their internal IPs
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'

# Get all container images across all pods
k get pods -o jsonpath='{.items[*].spec.containers[*].image}' -A

# Get images with pod names
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Get pods on a specific node
k get pods -o jsonpath='{range .items[?(@.spec.nodeName=="node01")]}{.metadata.name}{"\n"}{end}'

# Get container names in a pod
k get pod nginx -o jsonpath='{.spec.containers[*].name}'

# Get pod IPs
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'

# Get PV sorted by capacity
k get pv --sort-by=.spec.capacity.storage -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.capacity.storage}{"\n"}{end}'

# Get specific secret data (base64 decoded)
k get secret my-secret -o jsonpath='{.data.password}' | base64 -d

# Get service ClusterIPs
k get svc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.clusterIP}{"\n"}{end}'

# Get pods with restart count > 0
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# Get the scheduler name for a pod
k get pod nginx -o jsonpath='{.spec.schedulerName}'

# Get taints on a node
k get node node01 -o jsonpath='{.spec.taints}'

# Get all namespace names
k get ns -o jsonpath='{.items[*].metadata.name}'

# Get endpoints for a service
k get endpoints my-svc -o jsonpath='{.subsets[*].addresses[*].ip}'

# Custom columns alternative (often easier to read)
k get pods -o custom-columns='POD:.metadata.name,IMAGE:.spec.containers[0].image,NODE:.spec.nodeName'
k get pv -o custom-columns='NAME:.metadata.name,CAPACITY:.spec.capacity.storage,STATUS:.status.phase,CLAIM:.spec.claimRef.name'
```

---

## 9. Time-Saving Techniques

### Generate YAML Templates Quickly

```bash
# The "$do" variable is your best friend
# Step 1: Generate base YAML
k run nginx --image=nginx --port=80 $do > pod.yaml

# Step 2: Edit as needed
vi pod.yaml

# Step 3: Apply
k apply -f pod.yaml

# Works with all imperative commands
k create deployment nginx --image=nginx --replicas=3 $do > deploy.yaml
k create service clusterip my-svc --tcp=80:80 $do > svc.yaml
k create configmap my-cm --from-literal=key=val $do > cm.yaml
k create job my-job --image=busybox $do -- echo hi > job.yaml
```

### kubectl explain for Field Discovery

```bash
# Don't memorize every field — use explain
k explain pod.spec.containers.resources
k explain pod.spec.affinity.nodeAffinity
k explain deployment.spec.strategy.rollingUpdate
k explain pod.spec.tolerations
k explain pod.spec.volumes.persistentVolumeClaim

# Recursive gives you the full tree
k explain pod.spec.securityContext --recursive | grep -i "runAsUser"
k explain networkpolicy.spec --recursive
```

### Using grep and sort with kubectl

```bash
# Find specific resources
k get pods -A | grep -i error
k get events -A --sort-by=.metadata.creationTimestamp | tail -20
k get pods -A | grep -v Running    # Non-running pods

# Count resources
k get pods -A --no-headers | wc -l
k get pods -A --no-headers -l app=nginx | wc -l

# Find which node a pod is on
k get pods -o wide | grep nginx

# Find pods not in Running state
k get pods -A --field-selector=status.phase!=Running

# Multi-resource get
k get pods,svc,deployments
k get all    # Common resources in namespace
```

### Exam-Critical Workflows

```bash
# 1. Quick pod with volume (generate then edit)
k run nginx --image=nginx $do > pod.yaml
# Edit to add volume and volumeMount, then apply

# 2. Quick sidecar pattern
k run multi --image=nginx $do > multi.yaml
# Edit to add second container, then apply

# 3. Quick network policy
# No imperative command — use explain + template
k explain networkpolicy.spec --recursive
# Write from scratch or copy from docs

# 4. Create and expose in one flow
k create deployment nginx --image=nginx --replicas=3
k expose deployment nginx --port=80 --type=NodePort

# 5. Quick RBAC setup
k create sa my-sa
k create role my-role --verb=get,list --resource=pods
k create rolebinding my-binding --role=my-role --serviceaccount=default:my-sa
k auth can-i get pods --as=system:serviceaccount:default:my-sa

# 6. Quick resource check after creation
k run nginx --image=nginx && k get pod nginx -w
```

### Documentation Quick Access

```bash
# In exam, kubernetes.io/docs is available
# Key pages to bookmark/know:
# - kubectl cheat sheet
# - Tasks > Configure Pods and Containers
# - Tasks > Manage Resources
# - Concepts > Workloads
# - Reference > kubectl
```

---

## Quick Reference Card

| Task | Command |
|---|---|
| Create pod | `k run nginx --image=nginx` |
| Create deployment | `k create deploy nginx --image=nginx --replicas=3` |
| Expose deployment | `k expose deploy nginx --port=80 --type=ClusterIP` |
| Generate YAML | `k run nginx --image=nginx $do > pod.yaml` |
| Force delete | `k delete pod nginx $now` |
| Switch namespace | `kn my-namespace` |
| Debug pod | `k exec -it nginx -- sh` |
| Check logs | `k logs nginx -f --tail=100` |
| Check events | `k get events --sort-by=.metadata.creationTimestamp` |
| Node info | `k describe node node01` |
| RBAC check | `k auth can-i create pods --as=jane` |
| Rollback | `k rollout undo deploy/nginx` |
| Drain node | `k drain node01 --ignore-daemonsets --delete-emptydir-data` |
| Scale | `k scale deploy nginx --replicas=5` |
| Update image | `k set image deploy/nginx nginx=nginx:1.25` |

# CKAD — Certified Kubernetes Application Developer (Exam Guide & Mastery)

The Certified Kubernetes Application Developer (CKAD) certification verifies that you can design, build, configure, deploy, expose, and observe cloud-native applications on Kubernetes.

- **Exam Duration**: 120 minutes (2 hours)
- **Format**: ~16–19 hands-on performance tasks in CLI
- **Passing Score**: 66%
- **Allowed Resources**: Official docs (`kubernetes.io/docs`, `kubernetes.io/blog`, `github.com/kubernetes`, `helm.sh/docs`).

---

## 📊 Exam Domain Weights

| Domain | Weight | Key Competencies |
| :--- | :---: | :--- |
| **1. Application Environment, Config & Security** | **25%** | ConfigMaps, Secrets, SecurityContext, resource limits, ServiceAccounts |
| **2. Application Design and Build** | **20%** | Multi-container patterns (sidecar, init), Jobs, CronJobs, container optimization |
| **3. Application Deployment** | **20%** | Rolling updates, rollbacks, blue/green, canary, Helm packages |
| **4. Services and Networking** | **20%** | Services (ClusterIP, NodePort), Ingress, NetworkPolicies |
| **5. Application Observability & Maintenance** | **15%** | Probes (startup, liveness, readiness), logs, debugging, metrics |

---

## 🔒 Domain 1: Application Environment, Config & Security (25%)

### 1.1 ConfigMaps and Secrets
Fast imperative creation:
```bash
# Literal ConfigMap & Secret
kubectl create configmap app-cfg --from-literal=ENVIRONMENT=production --from-literal=DB_PORT=5432
kubectl create secret generic app-sec --from-literal=DB_PASS=superSecret123

# From file or env file
kubectl create configmap config-from-file --from-file=config.properties
kubectl create secret generic env-secret --from-env-file=.env
```

Injecting as Environment Variables:
```yaml
spec:
  containers:
  - name: app
    image: alpine
    command: ["sh", "-c", "env && sleep 3600"]
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: app-sec
          key: DB_PASS
    # Or load ALL keys as environment variables:
    envFrom:
    - configMapRef:
        name: app-cfg
```

Mounting as Volumes:
```yaml
spec:
  containers:
  - name: web
    image: nginx
    volumeMounts:
    - name: cfg-vol
      mountPath: /etc/config
      readOnly: true
  volumes:
  - name: cfg-vol
    configMap:
      name: app-cfg
```

### 1.2 SecurityContext & Linux Capabilities
```yaml
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
  containers:
  - name: sec-container
    image: busybox
    command: ["sh", "-c", "sleep 3600"]
    securityContext:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - "ALL"
        add:
        - "NET_BIND_SERVICE"
```

### 1.3 Resource Requests and Limits
```yaml
resources:
  requests:
    cpu: "250m"       # 0.25 core
    memory: "128Mi"
  limits:
    cpu: "500m"       # Throttled if exceeded
    memory: "256Mi"   # OOMKilled if exceeded
```

---

## 🧱 Domain 2: Application Design and Build (20%)

### 2.1 Multi-Container Pod Patterns

#### Sidecar Pattern (Log Aggregator/Proxy)
Containers run simultaneously and share volumes/localhost:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-pod
spec:
  containers:
  - name: app-writer
    image: busybox
    command: ["sh", "-c", "while true; do date >> /var/log/app.log; sleep 2; done"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log
  - name: sidecar-reader
    image: busybox
    command: ["sh", "-c", "tail -n+1 -F /var/log/app.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log
  volumes:
  - name: shared-logs
    emptyDir: {}
```

#### Init Containers (Sequencing & Pre-requisites)
Run to completion in sequence before main containers start:
```yaml
spec:
  initContainers:
  - name: wait-for-db
    image: busybox:1.28
    command: ['sh', '-c', 'until nc -z -w 2 db-service 5432; do echo waiting for db; sleep 2; done']
  containers:
  - name: web-app
    image: nginx
```

### 2.2 Jobs and CronJobs
```bash
# Imperative creation
kubectl create job oneshot-job --image=perl:5.34 -- perl -Mbignum=bpi -w -e 'print bpi(100)'
kubectl create cronjob nightly-report --image=busybox --schedule="0 1 * * *" -- sh -c "echo Generating report; sleep 5"
```
Key specs:
- `completions`: Total desired successful completions
- `parallelism`: Maximum simultaneous pods
- `backoffLimit`: Max retries on failure (default 6)
- `concurrencyPolicy`: `Allow`, `Forbid`, or `Replace`

---

## 🚀 Domain 3: Application Deployment (20%)

### 3.1 Rolling Updates & Rollbacks
```bash
# Update image
kubectl set image deployment/frontend nginx=nginx:1.27.0 --record

# Check rollout status and history
kubectl rollout status deployment/frontend
kubectl rollout history deployment/frontend

# Rollback to immediate previous or specific revision
kubectl rollout undo deployment/frontend
kubectl rollout undo deployment/frontend --to-revision=2

# Pause and resume updates
kubectl rollout pause deployment/frontend
kubectl rollout resume deployment/frontend
```

Deployment Strategy Specs:
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%          # Extra pods allowed above replica count during update
      maxUnavailable: 25%    # Max missing pods during update
```

### 3.2 Helm Operations (Package Management)
```bash
# Add repo & search
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo redis

# Install with custom values
helm install my-redis bitnami/redis --set auth.enabled=false -n dev --create-namespace

# Inspect values & upgrade
helm show values bitnami/redis > custom-values.yaml
helm upgrade my-redis bitnami/redis -f custom-values.yaml -n dev

# Rollback and uninstall
helm history my-redis -n dev
helm rollback my-redis 1 -n dev
helm uninstall my-redis -n dev
```

---

## 🌐 Domain 4: Services and Networking (20%)

### 4.1 Exposing Applications
```bash
# Create Service targeting pods matching labels
kubectl expose deployment frontend --name=frontend-svc --type=ClusterIP --port=80 --target-port=8080
kubectl expose pod nginx-pod --name=nginx-np --type=NodePort --port=80
```

### 4.2 Network Policies for Applications
Isolate pod so it only accepts traffic from specific backend pods:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-netpol
  namespace: prod
spec:
  podSelector:
    matchLabels:
      role: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: backend
    ports:
    - protocol: TCP
      port: 5432
```

---

## 🩺 Domain 5: Observability & Maintenance (15%)

### 5.1 Health Probes
```yaml
containers:
- name: web
  image: nginx
  # Startup Probe: Grants initial grace time for slow booting apps
  startupProbe:
    httpGet:
      path: /healthz
      port: 80
    failureThreshold: 30
    periodSeconds: 10
  # Liveness Probe: Restarts pod if failing
  livenessProbe:
    httpGet:
      path: /healthz
      port: 80
    initialDelaySeconds: 15
    periodSeconds: 10
    failureThreshold: 3
  # Readiness Probe: Cuts traffic (removes from Endpoints) if failing
  readinessProbe:
    httpGet:
      path: /ready
      port: 80
    initialDelaySeconds: 5
    periodSeconds: 5
```

### 5.2 Container Logging & Ephemeral Debugging
```bash
# Live logs stream
kubectl logs -f deployment/frontend -c web-container --tail=50

# Logs from previous dead container instance
kubectl logs pod-name -c web-container --previous

# Attach interactive ephemeral debug container (Kubernetes 1.25+)
kubectl debug -it pod-name --image=busybox:1.28 --target=web-container
```

---

## 💡 Top CKAD Exam Tips

1. **Muscle memory for generators**:
   - `k run <name> --image=<img应用> $do > pod.yaml`
   - `k create deployment <name> --image=<img> --replicas=3 $do > dep.yaml`
   - `k create job <name> --image=<img> $do > job.yaml`
2. **Editing existing resources on the fly**:
   - `kubectl edit deploy <name>` or `kubectl get deploy <name> -o yaml > d.yaml` -> edit -> `kubectl replace -f d.yaml --force`
3. **Never guess labels**: Always check Pod labels before creating Services or NetworkPolicies (`kubectl get pods --show-labels`).


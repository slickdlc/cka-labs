# KCNA – Kubernetes and Cloud Native Associate Reference Guide

> **Exam Format:** Multiple-choice · 90 minutes · 60 questions · 75% passing score
> **Certification Body:** CNCF / Linux Foundation
> **Validity:** 3 years

---

## Domain 1: Kubernetes Fundamentals (44%)

This is the highest-weighted domain — nearly half the exam. Master every concept here.

### 1.1 Control Plane Components

The **control plane** manages the cluster's desired state and responds to events.

| Component | Role | Default Port |
|---|---|---|
| **kube-apiserver** | Front-end REST API for all cluster operations. All components communicate through it. Validates and processes API requests, serves as the single source of truth gateway. | 6443 |
| **etcd** | Distributed key-value store that persists all cluster state. Only the API server communicates with etcd directly. Uses the Raft consensus algorithm. | 2379-2380 |
| **kube-controller-manager** | Runs controller loops (Deployment, ReplicaSet, Node, Job, ServiceAccount controllers, etc.) that reconcile current state with desired state. | 10257 |
| **kube-scheduler** | Assigns Pods to Nodes based on resource requests, affinity/anti-affinity, taints/tolerations, and scheduling policies. Two phases: filtering then scoring. | 10259 |
| **cloud-controller-manager** | Integrates with cloud provider APIs (load balancers, routes, volumes). Only present in cloud-managed clusters. | 10258 |

**Key concept:** The control plane implements a **reconciliation loop** — controllers continuously compare the *desired state* (stored in etcd) with the *current state* (reported by kubelets) and take action to converge them.

### 1.2 Worker Node Components

| Component | Role |
|---|---|
| **kubelet** | Node agent that ensures containers described in PodSpecs are running and healthy. Communicates with the API server and manages the container runtime via CRI. |
| **kube-proxy** | Maintains network rules (iptables/IPVS) on each node to implement Services. Enables service discovery and load balancing within the cluster. |
| **Container Runtime** | Software that runs containers. Must implement the Container Runtime Interface (CRI). Examples: containerd, CRI-O. Docker (via dockershim) was removed in Kubernetes v1.24. |

### 1.3 Core Kubernetes Resources

#### Pods
- Smallest deployable unit in Kubernetes
- One or more containers sharing network namespace (localhost) and storage volumes
- Ephemeral by nature — not self-healing without a controller
- Each Pod gets its own IP address
- Defined with `kind: Pod` in YAML manifests

#### Deployments
- Manages ReplicaSets, which manage Pods
- Provides declarative updates for Pods
- Supports rolling updates, rollbacks, scaling
- Records revision history (`kubectl rollout history`)
- Strategy types: `RollingUpdate` (default) and `Recreate`

#### ReplicaSets
- Ensures a specified number of Pod replicas are running
- Uses label selectors to identify Pods it manages
- Usually managed by a Deployment (don't create directly)
- Replacement for the older ReplicationController

#### Services
- Stable networking abstraction that exposes Pods
- Provides a stable DNS name and IP (ClusterIP) for a set of Pods
- Types:
  - **ClusterIP** (default): Internal-only, accessible within the cluster
  - **NodePort**: Exposes service on each node's IP at a static port (30000-32767)
  - **LoadBalancer**: Provisions an external load balancer (cloud environments)
  - **ExternalName**: Maps to an external DNS name (CNAME record)

#### Namespaces
- Virtual clusters within a physical cluster for multi-tenancy and organization
- Default namespaces: `default`, `kube-system`, `kube-public`, `kube-node-lease`
- Resource quotas and limit ranges can be applied per namespace
- Most resources are namespace-scoped; some (Nodes, PersistentVolumes, ClusterRoles) are cluster-scoped

### 1.4 Configuration Resources

#### ConfigMaps
- Store non-confidential configuration data as key-value pairs
- Can be consumed as environment variables, command-line arguments, or mounted as files
- Decouples configuration from container images
- Not encrypted — don't use for sensitive data

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_ENV: "production"
  config.yaml: |
    server:
      port: 8080
```

#### Secrets
- Store sensitive data (passwords, tokens, keys)
- Base64-encoded by default (**not encrypted** unless encryption at rest is configured)
- Types: `Opaque`, `kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`, `kubernetes.io/service-account-token`
- Mounted as files or exposed as environment variables
- Best practice: Use external secret managers (Vault, AWS Secrets Manager) for production

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  username: YWRtaW4=      # base64 encoded "admin"
  password: cGFzc3dvcmQ=  # base64 encoded "password"
```

### 1.5 Volumes

| Volume Type | Description |
|---|---|
| **emptyDir** | Temporary storage, created when Pod is assigned to a node, deleted when Pod is removed |
| **hostPath** | Mounts a file or directory from the host node's filesystem (use with caution) |
| **PersistentVolume (PV)** | Cluster-level storage resource provisioned by an admin or dynamically via StorageClass |
| **PersistentVolumeClaim (PVC)** | A user's request for storage; binds to a PV |
| **configMap / secret** | Mount ConfigMap or Secret data as files |
| **nfs, csi, cloud-specific** | Network and cloud-backed storage options |

**PV Access Modes:**
- `ReadWriteOnce` (RWO): Single node read-write
- `ReadOnlyMany` (ROX): Multiple nodes read-only
- `ReadWriteMany` (RWX): Multiple nodes read-write
- `ReadWriteOncePod` (RWOP): Single pod read-write

**Reclaim Policies:** `Retain`, `Delete`, `Recycle` (deprecated)

### 1.6 kubectl Basics

```bash
# Resource management
kubectl get pods -n <namespace>          # List pods
kubectl describe pod <name>              # Detailed info
kubectl logs <pod> [-c <container>]      # View logs
kubectl exec -it <pod> -- /bin/sh        # Interactive shell
kubectl apply -f manifest.yaml           # Declarative create/update
kubectl delete -f manifest.yaml          # Delete resources
kubectl create deployment nginx --image=nginx  # Imperative creation

# Cluster info
kubectl cluster-info                     # Cluster endpoint info
kubectl get nodes                        # List nodes
kubectl api-resources                    # All resource types
kubectl explain pod.spec.containers      # API documentation

# Debugging
kubectl get events --sort-by='.lastTimestamp'
kubectl top pods                         # Resource usage (requires metrics-server)
```

### 1.7 Declarative API Model

- Kubernetes uses a **declarative model**: you describe the *desired state* in YAML/JSON, and controllers work to achieve it
- `kubectl apply` is the declarative approach (vs. imperative `kubectl create`)
- Every resource has: `apiVersion`, `kind`, `metadata`, `spec` (desired state), and `status` (current state — managed by the system)
- The API server validates requests against the OpenAPI schema
- Resources are organized into API groups: core (`v1`), `apps/v1`, `batch/v1`, `networking.k8s.io/v1`, etc.

### 1.8 YAML Manifest Structure

```yaml
apiVersion: apps/v1          # API group and version
kind: Deployment             # Resource type
metadata:
  name: nginx-deployment     # Resource name
  namespace: default         # Namespace (optional)
  labels:                    # Key-value metadata
    app: nginx
spec:                        # Desired state
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:                  # Pod template
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
```

---

## Domain 2: Container Orchestration (28%)

### 2.1 Container Basics

- Containers package application code with its dependencies and runtime
- Use Linux kernel features: **namespaces** (isolation), **cgroups** (resource limits), **union filesystems** (layered images)
- Container images are immutable, layered filesystem snapshots
- Images are stored in registries (Docker Hub, GCR, ECR, Quay, Harbor)
- Image naming: `registry/repository:tag` (e.g., `docker.io/library/nginx:1.25`)
- Image digest: `nginx@sha256:abc123...` — immutable reference

### 2.2 OCI Standards

The **Open Container Initiative (OCI)** defines industry standards:
- **OCI Image Spec**: Format for container images (layers, config, manifest)
- **OCI Runtime Spec**: How to run a container (filesystem bundle, lifecycle)
- **OCI Distribution Spec**: API for distributing images (push/pull from registries)

These standards ensure interoperability across different runtimes and tools.

### 2.3 Container Runtimes

| Runtime | Description |
|---|---|
| **containerd** | Industry-standard runtime, graduated CNCF project. Default in most Kubernetes distributions. Manages complete container lifecycle. |
| **CRI-O** | Lightweight runtime specifically designed for Kubernetes. Implements CRI directly. Used by OpenShift/OKD. |
| **runc** | Low-level OCI runtime that actually creates and runs containers. Used by both containerd and CRI-O under the hood. |

**Container Runtime Interface (CRI):** gRPC API that kubelet uses to communicate with any compliant container runtime. Decouples kubelet from specific runtime implementations.

### 2.4 Pod Lifecycle

```
Pending → Running → Succeeded/Failed
              ↓
           Unknown (node communication lost)
```

| Phase | Description |
|---|---|
| **Pending** | Pod accepted but containers not yet running. May be downloading images or waiting to be scheduled. |
| **Running** | Pod bound to a node, at least one container running or starting/restarting. |
| **Succeeded** | All containers terminated successfully (exit code 0) and will not restart. |
| **Failed** | All containers terminated, at least one with failure (non-zero exit code). |
| **Unknown** | Pod state cannot be determined, typically due to node communication failure. |

### 2.5 Container States

Within a running Pod, each container has one of three states:

| State | Description |
|---|---|
| **Waiting** | Container is not yet running (pulling image, applying Secrets, etc.) |
| **Running** | Container is executing without issues |
| **Terminated** | Container finished execution (successfully or with failure) |

**Restart Policies** (set at Pod level):
- `Always` (default): Always restart containers
- `OnFailure`: Restart only on non-zero exit code
- `Never`: Never restart

### 2.6 Resource Requests and Limits

```yaml
resources:
  requests:          # Guaranteed resources (used for scheduling)
    cpu: "250m"      # 250 millicores = 0.25 CPU
    memory: "128Mi"  # 128 mebibytes
  limits:            # Maximum resources (enforced at runtime)
    cpu: "500m"
    memory: "256Mi"
```

- **Requests**: Minimum guaranteed resources. Scheduler uses these to place Pods.
- **Limits**: Maximum resources a container can use.
- If a container exceeds its memory limit → **OOMKilled**
- If a container exceeds its CPU limit → **throttled** (not killed)
- **QoS Classes**:
  - `Guaranteed`: requests == limits for all containers
  - `Burstable`: At least one request set, but not all match limits
  - `BestEffort`: No requests or limits set (first to be evicted)

### 2.7 Scheduling

The scheduler assigns Pods to Nodes in two phases:

1. **Filtering**: Eliminate nodes that don't meet requirements (resource availability, node selectors, taints, affinity rules)
2. **Scoring**: Rank remaining nodes based on optimization criteria

**Scheduling mechanisms:**
- **nodeSelector**: Simple key-value label matching
- **Node Affinity**: Flexible rules (`requiredDuringScheduling`, `preferredDuringScheduling`)
- **Pod Affinity/Anti-Affinity**: Schedule relative to other Pods
- **Taints & Tolerations**: Nodes repel Pods unless they tolerate the taint
  - Effects: `NoSchedule`, `PreferNoSchedule`, `NoExecute`
- **PriorityClasses**: Higher-priority Pods can preempt lower-priority ones

### 2.8 Networking Fundamentals

**Kubernetes Networking Model** (four requirements):
1. Every Pod gets its own IP address
2. Pods on any node can communicate with all Pods on any other node without NAT
3. Agents on a node can communicate with all Pods on that node
4. Pods in the host network can communicate with all Pods on any node without NAT

**CNI (Container Network Interface):**
- Plugin-based networking for Kubernetes
- Popular CNI plugins: Calico, Cilium, Flannel, Weave Net
- CNI plugins implement the pod network and may also provide Network Policies

**DNS:**
- CoreDNS provides cluster DNS (replaced kube-dns)
- Service DNS: `<service-name>.<namespace>.svc.cluster.local`
- Pod DNS: `<pod-ip-dashed>.<namespace>.pod.cluster.local`

### 2.9 Network Policies

- Control traffic flow at the Pod level (L3/L4 firewall rules)
- Require a CNI plugin that supports Network Policies (Calico, Cilium, etc.)
- Default: All traffic is allowed. Once a NetworkPolicy selects a Pod, all non-matching traffic is denied.
- Can filter by: Pod labels, namespace labels, IP blocks (CIDR)
- Specify `ingress` (incoming) and/or `egress` (outgoing) rules

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
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
```

### 2.10 Service Discovery and Load Balancing

**Service Discovery methods:**
1. **DNS** (preferred): CoreDNS creates DNS records for Services
2. **Environment variables**: Injected into Pods at creation time

**Load Balancing:**
- kube-proxy distributes traffic across healthy Pod endpoints
- Modes: iptables (default), IPVS (better performance at scale), nftables
- Services use label selectors to identify target Pods
- **Endpoints/EndpointSlices**: Track the actual Pod IPs behind a Service

**Headless Services** (`clusterIP: None`):
- No cluster IP assigned
- DNS returns individual Pod IPs
- Used for StatefulSets and direct pod-to-pod communication

### 2.11 Autoscaling

| Autoscaler | Scope | Scales | Based On |
|---|---|---|---|
| **HPA** (Horizontal Pod Autoscaler) | Pods | Replica count | CPU, memory, custom metrics |
| **VPA** (Vertical Pod Autoscaler) | Pods | Resource requests/limits | Historical usage |
| **Cluster Autoscaler** | Nodes | Node count | Pending pods (unschedulable) |
| **KEDA** | Pods | Replica count (event-driven) | External event sources (queues, streams) |

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

## Domain 3: Cloud Native Application Delivery (16%)

### 3.1 CI/CD Concepts

**Continuous Integration (CI):**
- Developers frequently merge code into a shared repository
- Automated build, test, and validation on every commit
- Catches integration issues early
- Tools: Jenkins, GitHub Actions, GitLab CI, Tekton, CircleCI

**Continuous Delivery (CD):**
- Automated deployment pipeline that can release to any environment
- Every change is potentially deployable
- May require manual approval for production
- **Continuous Deployment** goes further: every change is automatically deployed

**Deployment Strategies:**

| Strategy | Description | Risk | Rollback Speed |
|---|---|---|---|
| **Rolling Update** | Gradually replace old pods with new ones | Low | Moderate |
| **Blue/Green** | Run two identical environments, switch traffic | Low | Fast (switch back) |
| **Canary** | Route small percentage of traffic to new version | Very Low | Fast |
| **Recreate** | Kill all old pods, then create new ones | High (downtime) | Slow |
| **A/B Testing** | Route based on user attributes | Low | Fast |

### 3.2 Helm Charts

**Helm** is the package manager for Kubernetes (CNCF Graduated project).

- **Chart**: A package of pre-configured Kubernetes resources
- **Release**: An instance of a chart deployed to a cluster
- **Repository**: Where charts are stored and shared
- **Values**: Configuration parameters that customize a chart

**Chart structure:**
```
mychart/
├── Chart.yaml          # Chart metadata (name, version, dependencies)
├── values.yaml         # Default configuration values
├── charts/             # Dependency charts
├── templates/          # Kubernetes manifest templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── _helpers.tpl    # Template helpers
│   └── NOTES.txt       # Post-install notes
└── .helmignore         # Files to ignore
```

**Key commands:**
```bash
helm install <release> <chart>        # Install a chart
helm upgrade <release> <chart>        # Upgrade a release
helm rollback <release> <revision>    # Rollback to a previous revision
helm list                             # List releases
helm repo add <name> <url>            # Add a chart repository
helm template <chart>                 # Render templates locally
helm uninstall <release>              # Remove a release
```

### 3.3 GitOps

**GitOps** uses Git as the single source of truth for declarative infrastructure and applications.

**Core principles:**
1. **Declarative**: System described declaratively (YAML manifests)
2. **Versioned and immutable**: All changes tracked in Git
3. **Pulled automatically**: Agents pull desired state from Git
4. **Continuously reconciled**: Software agents ensure actual state matches desired state

**ArgoCD:**
- Declarative GitOps CD tool for Kubernetes (CNCF Graduated)
- Watches Git repositories and syncs to cluster
- Web UI for visualizing application state
- Supports Helm, Kustomize, plain YAML, Jsonnet
- Concepts: Application, AppProject, ApplicationSet
- Sync strategies: manual, automatic, self-heal, auto-prune

**Flux:**
- GitOps toolkit for Kubernetes (CNCF Graduated)
- Modular architecture using Kubernetes controllers
- Components: Source Controller, Kustomize Controller, Helm Controller, Notification Controller
- Integrates natively with Helm and Kustomize
- Supports multi-tenancy

### 3.4 Troubleshooting Basics

| Symptom | Common Causes | Diagnosis |
|---|---|---|
| **CrashLoopBackOff** | Application error, missing config, wrong command | `kubectl logs`, `kubectl describe pod` |
| **ImagePullBackOff** | Wrong image name/tag, private registry auth, network issue | `kubectl describe pod` (Events section) |
| **Pending** | Insufficient resources, no matching node, unbound PVC | `kubectl describe pod`, `kubectl get events` |
| **OOMKilled** | Container exceeded memory limit | Increase memory limit or fix memory leak |
| **CreateContainerConfigError** | Missing ConfigMap or Secret referenced by Pod | Verify ConfigMap/Secret exists in namespace |
| **ErrImagePull** | Registry unreachable, image doesn't exist | Check image name and registry connectivity |
| **RunContainerError** | Bad entrypoint/command, missing mount path | `kubectl describe pod`, check container spec |

**Troubleshooting workflow:**
1. `kubectl get pods` — Check pod status
2. `kubectl describe pod <name>` — Look at Events section
3. `kubectl logs <pod> [-c container] [--previous]` — Check application logs
4. `kubectl get events --sort-by='.lastTimestamp'` — Cluster events
5. `kubectl exec -it <pod> -- /bin/sh` — Interactive debugging

---

## Domain 4: Cloud Native Architecture (12%)

### 4.1 Microservices vs. Monolithic Architecture

| Aspect | Monolithic | Microservices |
|---|---|---|
| **Structure** | Single deployable unit | Multiple independent services |
| **Scaling** | Scale entire application | Scale individual services |
| **Deployment** | All-or-nothing | Independent deployment per service |
| **Technology** | Single tech stack | Polyglot (different languages/frameworks) |
| **Data** | Shared database | Database per service |
| **Complexity** | Simpler initially | Operational complexity (networking, observability) |
| **Failure** | Single point of failure | Partial failure, need resilience patterns |
| **Team** | Single team | Small, autonomous teams per service |

### 4.2 The 12-Factor App

Methodology for building cloud-native applications:

| Factor | Principle |
|---|---|
| 1. **Codebase** | One codebase tracked in version control, many deploys |
| 2. **Dependencies** | Explicitly declare and isolate dependencies |
| 3. **Config** | Store config in the environment (not in code) |
| 4. **Backing services** | Treat backing services as attached resources |
| 5. **Build, release, run** | Strictly separate build and run stages |
| 6. **Processes** | Execute the app as one or more stateless processes |
| 7. **Port binding** | Export services via port binding |
| 8. **Concurrency** | Scale out via the process model |
| 9. **Disposability** | Maximize robustness with fast startup and graceful shutdown |
| 10. **Dev/prod parity** | Keep development, staging, and production as similar as possible |
| 11. **Logs** | Treat logs as event streams |
| 12. **Admin processes** | Run admin/management tasks as one-off processes |

### 4.3 Service Mesh

A **service mesh** provides infrastructure-layer handling of service-to-service communication.

**What it provides:**
- Mutual TLS (mTLS) encryption between services
- Traffic management (routing, retries, timeouts, circuit breaking)
- Observability (metrics, traces, logs)
- Access control and policy enforcement

**Architecture:** Typically uses a **sidecar proxy** pattern (data plane) managed by a control plane.

| Service Mesh | Key Features |
|---|---|
| **Istio** | Most feature-rich. Uses Envoy proxies. Virtual Services, Destination Rules, Gateways. CNCF project. |
| **Linkerd** | Lightweight, simple. Uses its own Rust-based micro-proxy. Graduated CNCF project. Focuses on simplicity and performance. |
| **Cilium Service Mesh** | eBPF-based, sidecar-less option. High performance. CNCF Graduated. |

### 4.4 API Gateways

- Single entry point for external traffic into the cluster
- Functions: routing, rate limiting, authentication, TLS termination, request transformation
- Kubernetes Gateway API: Newer, more expressive alternative to Ingress
- **Ingress**: Original Kubernetes resource for HTTP routing (being superseded by Gateway API)
- Popular: NGINX Ingress, Traefik, Kong, Ambassador/Emissary, Envoy Gateway

### 4.5 Observability

The three pillars of observability:

| Pillar | Purpose | Key Tool |
|---|---|---|
| **Metrics** | Numerical measurements over time (counters, gauges, histograms) | **Prometheus** (CNCF Graduated) |
| **Logging** | Event records from applications and infrastructure | **Fluentd** / **Fluent Bit** (CNCF Graduated / Incubating) |
| **Tracing** | Request flow across distributed services | **Jaeger** (CNCF Graduated) |

**Prometheus:**
- Pull-based metrics collection (scrapes HTTP endpoints)
- PromQL query language
- Built-in alerting via Alertmanager
- Time-series database
- Service discovery for Kubernetes

**Grafana:**
- Visualization and dashboarding platform
- Integrates with Prometheus, Loki, Jaeger, and many data sources
- Pre-built dashboards for Kubernetes monitoring

**Jaeger:**
- Distributed tracing system
- Implements OpenTelemetry
- Visualizes request paths across microservices
- Identifies latency bottlenecks

**OpenTelemetry (OTel):**
- CNCF Incubating project providing unified observability framework
- Vendor-neutral APIs, SDKs, and tools for metrics, logs, and traces
- Becoming the standard for cloud-native observability

### 4.6 CNCF Ecosystem

The **Cloud Native Computing Foundation** hosts projects across maturity levels:

| Level | Meaning | Example Projects |
|---|---|---|
| **Graduated** | Mature, production-ready, widely adopted | Kubernetes, Prometheus, Envoy, containerd, CoreDNS, etcd, Fluentd, Helm, Jaeger, Linkerd, ArgoCD, Flux, Cilium, Harbor, OPA, Vitess, TUF, Rook, SPIFFE/SPIRE |
| **Incubating** | Growing adoption, maturing | OpenTelemetry, gRPC, NATS, KubeVirt, Backstage, Dapr, Knative, Kyverno, CRI-O |
| **Sandbox** | Early stage, experimental | Various emerging projects |

**CNCF Trail Map** — Recommended journey:
1. Containerization → 2. CI/CD → 3. Orchestration → 4. Observability → 5. Service Mesh → 6. Networking/Policy → 7. Distributed Database → 8. Messaging → 9. Container Registry → 10. Software Distribution

---

## Practice Questions

### Domain 1: Kubernetes Fundamentals

**Q1.** Which control plane component is responsible for storing all cluster state data?

A) kube-apiserver
B) kube-controller-manager
C) etcd
D) kube-scheduler

**Answer: C) etcd** — etcd is the distributed key-value store that persists all Kubernetes cluster data. It's the only stateful component in the control plane.

---

**Q2.** What is the correct order of fields in a Kubernetes YAML manifest?

A) kind, apiVersion, spec, metadata
B) apiVersion, kind, metadata, spec
C) metadata, apiVersion, kind, spec
D) spec, metadata, kind, apiVersion

**Answer: B) apiVersion, kind, metadata, spec** — While YAML doesn't enforce order, the conventional and recommended order is apiVersion, kind, metadata, spec.

---

**Q3.** Which Service type provides an external load balancer in cloud environments?

A) ClusterIP
B) NodePort
C) LoadBalancer
D) ExternalName

**Answer: C) LoadBalancer** — LoadBalancer type provisions an external load balancer from the cloud provider and assigns a public IP.

---

**Q4.** What is the default namespace for resources when none is specified?

A) kube-system
B) kube-public
C) default
D) kube-node-lease

**Answer: C) default** — Resources are created in the `default` namespace when no namespace is specified.

---

**Q5.** A PersistentVolume with `accessMode: ReadWriteOnce` means:

A) The volume can be mounted as read-write by a single Pod
B) The volume can be mounted as read-write by a single Node
C) The volume can be mounted as read-write by all Pods
D) The volume can only be written to once

**Answer: B) The volume can be mounted as read-write by a single Node** — RWO means the volume can be mounted as read-write by a single node (multiple pods on that node may access it).

---

**Q6.** Which kubectl command should you use to apply changes declaratively?

A) `kubectl create -f manifest.yaml`
B) `kubectl apply -f manifest.yaml`
C) `kubectl replace -f manifest.yaml`
D) `kubectl update -f manifest.yaml`

**Answer: B) `kubectl apply -f manifest.yaml`** — `kubectl apply` is the declarative command that creates or updates resources based on the manifest file.

---

**Q7.** Secrets in Kubernetes are encoded using which format by default?

A) SHA-256
B) AES-256
C) Base64
D) MD5

**Answer: C) Base64** — Kubernetes Secrets are base64-encoded by default, which is encoding (not encryption). Encryption at rest must be separately configured.

---

### Domain 2: Container Orchestration

**Q8.** Which OCI specification defines the format for container images?

A) OCI Runtime Spec
B) OCI Image Spec
C) OCI Distribution Spec
D) OCI Network Spec

**Answer: B) OCI Image Spec** — The OCI Image Specification defines the format for container images, including layers, configuration, and manifest.

---

**Q9.** A Pod in `CrashLoopBackOff` status indicates:

A) The Pod is being scheduled to a node
B) The container is repeatedly crashing and Kubernetes is applying exponential backoff before restarting
C) The Pod is waiting for an image to be pulled
D) The node running the Pod is unreachable

**Answer: B)** — CrashLoopBackOff means the container keeps crashing and kubelet is waiting with exponentially increasing delays before restarting it.

---

**Q10.** What happens when a container exceeds its memory limit?

A) The container is CPU-throttled
B) The container is OOMKilled (terminated)
C) The Pod is evicted from the node
D) Nothing, limits are advisory

**Answer: B) The container is OOMKilled** — When a container exceeds its memory limit, the kernel's OOM killer terminates it. CPU overuse results in throttling, not termination.

---

**Q11.** Which QoS class is assigned when all containers in a Pod have equal requests and limits?

A) BestEffort
B) Burstable
C) Guaranteed
D) Premium

**Answer: C) Guaranteed** — When every container has matching CPU and memory requests and limits, the Pod gets Guaranteed QoS class.

---

**Q12.** Which container runtime replaced Docker as the default in Kubernetes v1.24+?

A) CRI-O
B) runc
C) containerd
D) Podman

**Answer: C) containerd** — containerd became the default container runtime after dockershim was removed in Kubernetes v1.24.

---

**Q13.** What does the HPA (Horizontal Pod Autoscaler) scale?

A) Node count in the cluster
B) CPU and memory limits of pods
C) The number of Pod replicas
D) The number of namespaces

**Answer: C) The number of Pod replicas** — HPA adjusts the number of Pod replicas in a Deployment/ReplicaSet based on metrics like CPU utilization.

---

**Q14.** Network Policies operate at which OSI layer(s)?

A) Layer 7 (Application)
B) Layer 3/4 (Network/Transport)
C) Layer 2 (Data Link)
D) Layer 1 (Physical)

**Answer: B) Layer 3/4** — Standard Kubernetes Network Policies filter at L3 (IP) and L4 (TCP/UDP port). Some CNI plugins like Cilium offer L7 policies as an extension.

---

### Domain 3: Cloud Native Application Delivery

**Q15.** In Helm, what is a "Release"?

A) A specific version of a Helm chart
B) An instance of a chart deployed to a cluster
C) A Helm repository
D) A template rendering

**Answer: B) An instance of a chart deployed to a cluster** — A Release is a running instance of a chart with a specific configuration (values).

---

**Q16.** Which of the following is a core principle of GitOps?

A) Changes are pushed directly to the cluster via CI/CD pipelines
B) Git is the single source of truth and changes are pulled by agents
C) Infrastructure is managed imperatively through scripts
D) Manual approval is always required for deployments

**Answer: B)** — GitOps uses Git as the source of truth with agents (like ArgoCD or Flux) pulling and reconciling the desired state.

---

**Q17.** ArgoCD and Flux are both examples of:

A) Container runtimes
B) Service meshes
C) GitOps tools
D) CI tools

**Answer: C) GitOps tools** — Both ArgoCD and Flux are CNCF Graduated GitOps continuous delivery tools for Kubernetes.

---

**Q18.** Which deployment strategy runs two complete environments and switches traffic between them?

A) Rolling Update
B) Canary
C) Blue/Green
D) Recreate

**Answer: C) Blue/Green** — Blue/Green runs two identical environments; traffic is switched from the old (blue) to the new (green) once validated.

---

### Domain 4: Cloud Native Architecture

**Q19.** Which 12-Factor App principle states that configuration should be stored in the environment?

A) Factor 2 (Dependencies)
B) Factor 3 (Config)
C) Factor 4 (Backing services)
D) Factor 6 (Processes)

**Answer: B) Factor 3 (Config)** — The third factor states that config that varies between deploys should be stored in environment variables, not in code.

---

**Q20.** What are the three pillars of observability?

A) Metrics, Logging, Tracing
B) Monitoring, Alerting, Dashboarding
C) Availability, Latency, Throughput
D) Authentication, Authorization, Auditing

**Answer: A) Metrics, Logging, Tracing** — The three pillars of observability are metrics (Prometheus), logs (Fluentd), and traces (Jaeger).

---

**Q21.** Which CNCF project maturity level indicates a project is production-ready and widely adopted?

A) Sandbox
B) Incubating
C) Graduated
D) Archived

**Answer: C) Graduated** — Graduated projects have demonstrated production readiness, wide adoption, and a healthy community.

---

**Q22.** A service mesh primarily provides which capabilities?

A) Container image building and storage
B) mTLS, traffic management, and observability between services
C) Persistent storage and backup
D) DNS resolution and certificate management

**Answer: B)** — A service mesh handles service-to-service communication concerns including mutual TLS encryption, traffic management, and observability.

---

**Q23.** In a microservices architecture, each service should ideally have:

A) Access to a shared database
B) Its own database (database per service)
C) No database — all state should be in-memory
D) A single shared message queue

**Answer: B) Its own database** — The database-per-service pattern ensures loose coupling. Each microservice manages its own data store.

---

**Q24.** Prometheus collects metrics using which method?

A) Push-based: applications send metrics to Prometheus
B) Pull-based: Prometheus scrapes HTTP endpoints
C) Agent-based: a Prometheus agent runs on each node
D) Log parsing: Prometheus reads application log files

**Answer: B) Pull-based** — Prometheus uses a pull model, scraping metrics from HTTP endpoints (typically `/metrics`) exposed by applications and exporters.

---

## Quick Reference: Key Facts for Exam Day

| Topic | Key Fact |
|---|---|
| Control plane port | API Server: 6443 |
| etcd | Only API server talks to etcd directly |
| Default Service type | ClusterIP |
| NodePort range | 30000-32767 |
| Pod networking | Every pod gets its own IP; no NAT between pods |
| Secrets encoding | Base64 (not encrypted by default) |
| Container runtime | containerd (default since K8s 1.24) |
| Memory overuse | OOMKilled |
| CPU overuse | Throttled (not killed) |
| Helm | CNCF Graduated; package manager for K8s |
| ArgoCD | CNCF Graduated; GitOps CD tool |
| Flux | CNCF Graduated; GitOps toolkit |
| Prometheus | Pull-based metrics; CNCF Graduated |
| Istio | Service mesh using Envoy sidecar proxies |
| Linkerd | Lightweight service mesh; CNCF Graduated |
| OCI | Image Spec, Runtime Spec, Distribution Spec |
| 12-Factor | Factor 3 = Config in environment |
| Observability | Metrics + Logs + Traces |

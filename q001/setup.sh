#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="ecommerce-prod"

echo "[SETUP] Initializing expert troubleshooting scenario: Multi-tier microservice outage..."

# 1. Clean up existing namespace idempotently
echo "[SETUP] Cleaning existing namespace '${NAMESPACE}' if present..."
kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true --timeout=30s 2>/dev/null || true

# 2. Create namespace
echo "[SETUP] Creating namespace '${NAMESPACE}'..."
kubectl create namespace "${NAMESPACE}"

# 3. Create database credentials Secret
echo "[SETUP] Creating database credentials Secret 'db-credentials'..."
kubectl create secret generic db-credentials \
  --namespace="${NAMESPACE}" \
  --from-literal=db_username="order_admin" \
  --from-literal=db_password="SuperSecretProductionPassword123!"

# 4. Deploy database backend and internal service
echo "[SETUP] Deploying backend database Pod and Service..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: order-db
  namespace: ${NAMESPACE}
  labels:
    app: order-db
spec:
  containers:
  - name: db-server
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo -e 'HTTP/1.1 200 OK\r\n\r\nDATABASE_OK' | nc -l -p 5432 || true; sleep 0.5; done"]
    ports:
    - containerPort: 5432
      name: postgres
---
apiVersion: v1
kind: Service
metadata:
  name: order-db-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: order-db
  ports:
  - protocol: TCP
    port: 5432
    targetPort: 5432
EOF

# 5. Deploy upstream client test Pod
echo "[SETUP] Deploying upstream client pod 'client-frontend'..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: client-frontend
  namespace: ${NAMESPACE}
  labels:
    app: client-frontend
spec:
  containers:
  - name: client
    image: curlimages/curl:8.6.0
    command: ["sh", "-c", "while true; do sleep 3600; done"]
EOF

# 6. Wait for prerequisites (order-db and client-frontend) to be Ready
echo "[SETUP] Waiting for dependency pods to become Ready..."
kubectl wait --namespace="${NAMESPACE}" --for=condition=Ready pod/order-db --timeout=60s
kubectl wait --namespace="${NAMESPACE}" --for=condition=Ready pod/client-frontend --timeout=60s

# 7. Inject Faults in Service 'order-service' (Mismatched selector and wrong targetPort)
echo "[SETUP] Creating misconfigured Service 'order-service'..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: order-service
  namespace: ${NAMESPACE}
spec:
  selector:
    app: order-api   # Fault 5a: Selector mismatch (Pods will have app: order-backend)
  ports:
  - protocol: TCP
    port: 80
    targetPort: 9090 # Fault 5b: targetPort mismatch (Container listens on port 80)
EOF

# 8. Inject Faults in NetworkPolicy 'order-netpol' (Mismatched Ingress selector & missing DB/DNS Egress)
echo "[SETUP] Creating restrictive NetworkPolicy 'order-netpol'..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-netpol
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: order-backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: web-gateway # Fault 6a: Ingress blocked; client pod has app: client-frontend
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: external-cache # Fault 6b: Egress to DNS (53) and DB (5432) blocked
    ports:
    - protocol: TCP
      port: 6379
EOF

# 9. Inject Faults in Deployment 'order-service'
# Fault 1: Invalid nodeSelector (pods stuck in Pending)
# Fault 2: Broken initContainer command querying non-existent hostname
# Fault 3: Secret key reference typo (db_pass instead of db_password)
# Fault 4: Readiness probe querying wrong port (8080) and wrong path (/health)
echo "[SETUP] Deploying multi-fault Deployment 'order-service'..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: ${NAMESPACE}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-backend
  template:
    metadata:
      labels:
        app: order-backend
    spec:
      nodeSelector:
        disktype: nvme-enterprise # Fault 1: Unsatisfiable nodeSelector (Pending state)
      initContainers:
      - name: init-db-check
        image: busybox:1.36
        command: ["sh", "-c", "nc -z -w 2 invalid-db-endpoint.ecommerce-prod.svc.cluster.local 5432"] # Fault 2: Broken host
      containers:
      - name: order-app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
          name: http
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: db_pass # Fault 3: Secret key is db_password
        readinessProbe: # Fault 4: Probe hitting invalid port and path
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 2
          periodSeconds: 3
EOF

echo "[SETUP] Setup complete. Environment 'ecommerce-prod' initialized with cascaded faults."
echo "[SETUP] Run 'kubectl get pods -n ecommerce-prod' to begin diagnosis."

# Step-by-Step Solution: Backend NetworkPolicy

## Fast Imperative / Declarative Approach

In the CKA exam, create the manifest quickly and apply it:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: ecommerce
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
EOF
```

## Quick Verification

```bash
# 1. Allowed connection (must succeed):
kubectl exec -n ecommerce frontend-app -- wget -qO- --timeout=3 http://backend-svc:8080

# 2. Blocked connection from rogue-client (must time out):
kubectl exec -n ecommerce rogue-client -- wget -qO- --timeout=3 http://backend-svc:8080

# 3. Blocked connection from external-client (must time out):
kubectl exec -n analytics external-client -- wget -qO- --timeout=3 http://backend-svc.ecommerce:8080
```

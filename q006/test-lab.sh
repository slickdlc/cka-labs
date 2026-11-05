#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== [TEST-LAB] Running Full Lifecycle Test for q006 ==="

# 1. Setup
echo "[TEST-LAB] Executing setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

# 2. Apply Reference Solution
echo "[TEST-LAB] Step 1: Scale down to 0 replicas..."
kubectl scale deployment wordpress -n default --replicas=0

echo "[TEST-LAB] Step 2: Patching initContainers and containers with matching fair-share resources..."
SAFE_CPU="200m"
SAFE_MEM="256Mi"

kubectl patch deployment wordpress -n default --type='strategic' -p "{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"initContainers\": [
          {
            \"name\": \"init-wordpress\",
            \"resources\": {
              \"requests\": { \"cpu\": \"$SAFE_CPU\", \"memory\": \"$SAFE_MEM\" },
              \"limits\": { \"cpu\": \"$SAFE_CPU\", \"memory\": \"$SAFE_MEM\" }
            }
          }
        ],
        \"containers\": [
          {
            \"name\": \"wordpress\",
            \"resources\": {
              \"requests\": { \"cpu\": \"$SAFE_CPU\", \"memory\": \"$SAFE_MEM\" },
              \"limits\": { \"cpu\": \"$SAFE_CPU\", \"memory\": \"$SAFE_MEM\" }
            }
          }
        ]
      }
    }
  }
}"

echo "[TEST-LAB] Step 3: Scaling deployment back to 3 replicas..."
kubectl scale deployment wordpress -n default --replicas=3

echo "[TEST-LAB] Waiting for deployment rollout..."
kubectl rollout status deployment/wordpress -n default --timeout=60s

# 3. Validate
echo "[TEST-LAB] Running validate.sh..."
bash "$SCRIPT_DIR/validate.sh"

# 4. Cleanup
echo "[TEST-LAB] Running cleanup.sh..."
bash "$SCRIPT_DIR/cleanup.sh"

echo "=== [TEST-LAB] Lifecycle test completed successfully. ==="


#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== [TEST-LAB] Running Full Lifecycle Test for q005 ==="

# 1. Setup
echo "[TEST-LAB] Executing setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

# 2. Apply Reference Solution
echo "[TEST-LAB] Applying reference solution..."
kubectl get deployment wordpress -n default -o json | \
jq '
  .spec.template.spec.volumes = [
    {
      "name": "wordpress-log-volume",
      "emptyDir": {}
    }
  ] |
  .spec.template.spec.containers[0].volumeMounts = [
    {
      "name": "wordpress-log-volume",
      "mountPath": "/var/log"
    }
  ] |
  .spec.template.spec.containers += [
    {
      "name": "sidecar",
      "image": "busybox:stable",
      "command": ["/bin/sh", "-c", "tail -f /var/log/wordpress.log"],
      "volumeMounts": [
        {
          "name": "wordpress-log-volume",
          "mountPath": "/var/log"
        }
      ]
    }
  ]
' | kubectl apply -f -

echo "[TEST-LAB] Waiting for deployment rollout..."
kubectl rollout status deployment/wordpress -n default --timeout=60s

# 3. Validate
echo "[TEST-LAB] Running validate.sh..."
bash "$SCRIPT_DIR/validate.sh"

# 4. Cleanup
echo "[TEST-LAB] Running cleanup.sh..."
bash "$SCRIPT_DIR/cleanup.sh"

echo "=== [TEST-LAB] Lifecycle test completed successfully. ==="

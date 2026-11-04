#!/usr/bin/env bash
set -euo pipefail

LAB_NAME="${1:-}"
DOMAIN="${2:-Workloads & Scheduling}"

if [ -z "$LAB_NAME" ]; then
  echo "Usage: $0 <lab-name> [cka-domain]"
  echo "Example: $0 lab-storage-pv 'Storage'"
  exit 1
fi

TARGET_DIR="./$LAB_NAME"
mkdir -p "$TARGET_DIR"

echo "Creating lab structure in '$TARGET_DIR'..."

# 1. metadata.yaml
cat <<EOF > "$TARGET_DIR/metadata.yaml"
id: $LAB_NAME
title: "$LAB_NAME"
domain: "$DOMAIN"
cka_weight: "15%"
difficulty: "Medium" # Easy | Medium | Hard
target_namespace: "cka-lab"
context: "default"
estimated_time_minutes: 8
skills_tested:
  - ResourceManagement
EOF

# 2. question.md
cat <<EOF > "$TARGET_DIR/question.md"
# Task: [Descriptive Title of the CKA Exercise]

**Context:**
Ensure you are operating in the \`default\` context.

**Target Namespace:**
\`cka-lab\`

**Requirements:**
1. Clear statement without hints.
2. Specify exact resource names, labels, and ports.
3. Specify the exact absolute path of any output files if applicable.
EOF

# 3. setup.sh
cat <<'EOF' > "$TARGET_DIR/setup.sh"
#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="cka-lab"
echo "[SETUP] Initializing lab environment..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true
kubectl create namespace "$NAMESPACE"

# Deploy initial state or inject faults here

echo "[SETUP] Environment ready."
EOF

# 4. validate.sh
cat <<'EOF' > "$TARGET_DIR/validate.sh"
#!/usr/bin/env bash
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TOTAL=0
PASSED=0
FAILED=0

pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  ((PASSED++))
  ((TOTAL++))
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  if [ -n "${2:-}" ]; then
    echo -e "       ${YELLOW}Detail:${NC} $2"
  fi
  ((FAILED++))
  ((TOTAL++))
}

echo "=== Evaluating CKA Lab ==="

# Validation checks here

echo "=========================="
echo -e "Total: $TOTAL | ${GREEN}Passed: $PASSED${NC} | ${RED}Failed: $FAILED${NC}"

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}SUCCESS! Lab passed.${NC}"
  exit 0
else
  echo -e "${RED}FAILURE! One or more checks failed.${NC}"
  exit 1
fi
EOF

# 5. cleanup.sh
cat <<'EOF' > "$TARGET_DIR/cleanup.sh"
#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="cka-lab"
echo "[CLEANUP] Cleaning up lab resources..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s
echo "[CLEANUP] Complete."
EOF

# 6. solution.md
cat <<'EOF' > "$TARGET_DIR/solution.md"
# Step-by-Step Solution (CKA Exam Technique)

## Fast Imperative Commands
```bash
# Imperative shortcuts here
```

## Reference Manifest
```yaml
# Manifest here
```
EOF

# 7. test-lab.sh
cat <<'EOF' > "$TARGET_DIR/test-lab.sh"
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Verifying Lab Reproducibility ==="
bash "$SCRIPT_DIR/setup.sh"
bash "$SCRIPT_DIR/validate.sh"
bash "$SCRIPT_DIR/cleanup.sh"
echo "=== Lab Reproducibility Verified ==="
EOF

chmod +x "$TARGET_DIR"/*.sh 2>/dev/null || true

echo "Lab '$LAB_NAME' successfully created in '$TARGET_DIR'."

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$LabName,

    [Parameter(Position = 1)]
    [string]$Domain = "Workloads & Scheduling"
)

$targetDir = Join-Path -Path (Get-Location) -ChildPath $LabName
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Creating lab structure in '$targetDir'..." -ForegroundColor Cyan

# 1. metadata.yaml
@"
id: $LabName
title: "$LabName"
domain: "$Domain"
cka_weight: "15%"
difficulty: "Medium" # Easy | Medium | Hard
target_namespace: "cka-lab"
context: "default"
estimated_time_minutes: 8
skills_tested:
  - ResourceManagement
"@ | Set-Content -Path (Join-Path $targetDir "metadata.yaml") -Encoding UTF8

# 2. question.md
@"
# Task: [Descriptive Title of the CKA Exercise]

**Context:**
Ensure you are operating in the \`default\` context.

**Target Namespace:**
\`cka-lab\`

**Requirements:**
1. Clear statement without hints.
2. Specify exact resource names, labels, and ports.
3. Specify the exact absolute path of any output files if applicable.
"@ | Set-Content -Path (Join-Path $targetDir "question.md") -Encoding UTF8

# 3. setup.sh
@'
#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="cka-lab"
echo "[SETUP] Initializing lab environment..."

kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=30s 2>/dev/null || true
kubectl create namespace "$NAMESPACE"

# Deploy initial state or inject faults here

echo "[SETUP] Environment ready."
'@ | Set-Content -Path (Join-Path $targetDir "setup.sh") -Encoding UTF8

# 4. validate.sh
@'
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
'@ | Set-Content -Path (Join-Path $targetDir "validate.sh") -Encoding UTF8

# 5. cleanup.sh
@'
#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="cka-lab"
echo "[CLEANUP] Cleaning up lab resources..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=60s
echo "[CLEANUP] Complete."
'@ | Set-Content -Path (Join-Path $targetDir "cleanup.sh") -Encoding UTF8

# 6. solution.md
@'
# Step-by-Step Solution (CKA Exam Technique)

## Fast Imperative Commands
```bash
# Imperative shortcuts here
```

## Reference Manifest
```yaml
# Manifest here
```
'@ | Set-Content -Path (Join-Path $targetDir "solution.md") -Encoding UTF8

# 7. test-lab.sh
@'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Verifying Lab Reproducibility ==="
bash "$SCRIPT_DIR/setup.sh"
bash "$SCRIPT_DIR/validate.sh"
bash "$SCRIPT_DIR/cleanup.sh"
echo "=== Lab Reproducibility Verified ==="
'@ | Set-Content -Path (Join-Path $targetDir "test-lab.sh") -Encoding UTF8

Write-Host "Lab '$LabName' successfully created in '$targetDir'." -ForegroundColor Green

#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="ecommerce"
OTHER_NS="analytics"

echo "[CLEANUP] Removing test namespaces '$NAMESPACE' and '$OTHER_NS'..."
kubectl delete namespace "$NAMESPACE" "$OTHER_NS" --ignore-not-found=true --timeout=60s

echo "[CLEANUP] Complete."

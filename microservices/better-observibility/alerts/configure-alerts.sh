#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v helm >/dev/null || { echo "helm is required"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }

if helm repo list | awk 'NR > 1 {print $1}' | grep -qx prometheus-community; then
  echo "Using the cached prometheus-community chart index."
else
  echo "Adding prometheus-community (the first index download can take about a minute)..."
  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts \
    --timeout 1m
fi

# Updates Alertmanager with the Mailpit email receiver.
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$ROOT/values/kube-prometheus-stack.yaml" \
  --wait --timeout 10m

kubectl apply -f "$ROOT/alerts/ecommerce-alerts.yaml"

echo
echo "Alert rules and Mailpit email delivery are configured."
echo "Open the inbox with:"
echo "  kubectl -n ecommerce port-forward svc/mailpit 8025:8025"
echo "Then visit http://localhost:8025"

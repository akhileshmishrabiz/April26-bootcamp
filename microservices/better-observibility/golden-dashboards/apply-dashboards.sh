#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }

if command -v jq >/dev/null; then
  for dashboard in "$DIR"/*.json; do
    jq empty "$dashboard"
  done
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create configmap ecommerce-golden-dashboards \
  --from-file="$DIR/services-golden-signals.json" \
  --from-file="$DIR/postgresql-cnpg.json" \
  --from-file="$DIR/service-logs.json" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" label configmap ecommerce-golden-dashboards \
  grafana_dashboard=1 \
  app.kubernetes.io/part-of=ecommerce-observability \
  --overwrite

echo "Applied 3 dashboards. Grafana's dashboard sidecar will load them shortly."

#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. Override these if your namespaces differ:
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
APP_NAMESPACE="${APP_NAMESPACE:-ecommerce}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v helm >/dev/null || { echo "helm is required"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }

echo "Using Kubernetes context: $(kubectl config current-context)"

ensure_helm_repo() {
  local name="$1"
  local url="$2"

  if helm repo list | awk 'NR > 1 {print $1}' | grep -qx "$name"; then
    echo "Helm repository '$name' already exists; using its cached index."
  else
    echo "Adding Helm repository '$name' (the first index download can take about a minute)..."
    helm repo add "$name" "$url" --timeout 1m
  fi
}

ensure_helm_repo prometheus-community https://prometheus-community.github.io/helm-charts
ensure_helm_repo grafana https://grafana.github.io/helm-charts

# Updating every configured Helm repository can look frozen and may take several
# minutes. Opt in only when a fresh chart index is actually needed.
if [[ "${UPDATE_HELM_REPOS:-false}" == "true" ]]; then
  echo "Refreshing the Prometheus and Grafana chart indexes..."
  helm repo update prometheus-community grafana --timeout 1m
fi

echo "Installing Prometheus, Alertmanager, and Grafana..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE" \
  --create-namespace \
  --values "$ROOT/values/kube-prometheus-stack.yaml" \
  --wait --timeout 10m

echo "Installing Loki..."
helm upgrade --install loki grafana/loki \
  --namespace "$MONITORING_NAMESPACE" \
  --values "$ROOT/values/loki.yaml" \
  --wait --timeout 10m

echo "Installing Promtail..."
helm upgrade --install promtail grafana/promtail \
  --namespace "$MONITORING_NAMESPACE" \
  --values "$ROOT/values/promtail.yaml" \
  --wait --timeout 10m

# These can be applied before the app exists and discover targets later.
for monitor in services-servicemonitor.yaml cnpg-podmonitor.yaml; do
  sed \
    -e "s/  namespace: monitoring/  namespace: ${MONITORING_NAMESPACE}/" \
    -e "s/      - ecommerce/      - ${APP_NAMESPACE}/" \
    "$ROOT/manifests/$monitor" | kubectl apply -f -
done

"$ROOT/golden-dashboards/apply-dashboards.sh"
kubectl apply -f "$ROOT/alerts/ecommerce-alerts.yaml"

cat <<EOF

Observability is ready.

Grafana:
  kubectl -n ${MONITORING_NAMESPACE} port-forward svc/monitoring-grafana 3000:80
  Open http://localhost:3000 (admin / admin)

Prometheus:
  kubectl -n ${MONITORING_NAMESPACE} port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
  Open http://localhost:9090

Check targets:
  kubectl -n ${MONITORING_NAMESPACE} get pods

Mailpit alert inbox:
  kubectl -n ${APP_NAMESPACE} port-forward svc/mailpit 8025:8025
  Open http://localhost:8025
EOF

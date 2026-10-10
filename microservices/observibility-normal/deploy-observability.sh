#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OBSERVABILITY_NAMESPACE="observability"
APP_NAMESPACE="ecommerce"
EXPECTED_CLUSTER="ecommerce-ms-simple"
EXPECTED_CONTEXT="kind-${EXPECTED_CLUSTER}"
TIMEOUT="${TIMEOUT:-180s}"
MANIFESTS=(
  "00-namespace.yaml"
  "10-prometheus.yaml"
  "15-node-exporter.yaml"
  "20-loki.yaml"
  "30-promtail.yaml"
  "40-grafana.yaml"
)

info() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "'$1' is required. ${2}"
}

context_exists() {
  kubectl config get-contexts "$1" -o name 2>/dev/null | grep -Fxq "$1"
}

cluster_has_ecommerce_app() {
  local context="$1"

  kubectl --context "$context" get namespace "$APP_NAMESPACE" >/dev/null 2>&1 &&
    kubectl --context "$context" -n "$APP_NAMESPACE" get deployment/api-gateway >/dev/null 2>&1 &&
    kubectl --context "$context" -n "$APP_NAMESPACE" get deployment/product-service >/dev/null 2>&1
}

find_ecommerce_context() {
  local cluster context
  local -a clusters=()
  local -a candidates=()

  while IFS= read -r cluster; do
    [[ -n "$cluster" ]] && clusters+=("$cluster")
  done < <(kind get clusters 2>/dev/null)

  ((${#clusters[@]} > 0)) ||
    fail "No Kind clusters were found. Deploy the app first with:
  $SCRIPT_DIR/../helm-deployments-kind/helm-ms-simple/helm-deploy.sh"

  for cluster in "${clusters[@]}"; do
    [[ "$cluster" == "$EXPECTED_CLUSTER" ]] && candidates+=("$cluster")
  done
  for cluster in "${clusters[@]}"; do
    [[ "$cluster" != "$EXPECTED_CLUSTER" ]] && candidates+=("$cluster")
  done

  for cluster in "${candidates[@]}"; do
    context="kind-${cluster}"
    context_exists "$context" || continue
    if cluster_has_ecommerce_app "$context"; then
      printf '%s\n' "$context"
      return 0
    fi
  done

  fail "No Kind cluster contains the expected e-commerce app.
Expected namespace '$APP_NAMESPACE' with deployments 'api-gateway' and 'product-service'.
Deploy it first with:
  $SCRIPT_DIR/../helm-deployments-kind/helm-ms-simple/helm-deploy.sh
Then verify with:
  kubectl --context $EXPECTED_CONTEXT get deployments -n $APP_NAMESPACE"
}

info "Checking prerequisites"
require_command kind "Install it with: brew install kind"
require_command kubectl "Install it with: brew install kubectl"

# Kind uses Docker by default, but honors KIND_EXPERIMENTAL_PROVIDER for other
# supported local container providers.
CONTAINER_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-docker}"
case "$CONTAINER_PROVIDER" in
  docker)
    require_command docker "Install Docker Desktop, then start it."
    docker info >/dev/null 2>&1 ||
      fail "Docker is installed but unavailable. Start Docker Desktop and retry."
    ;;
  podman)
    require_command podman "Install and start Podman, or unset KIND_EXPERIMENTAL_PROVIDER to use Docker."
    podman info >/dev/null 2>&1 ||
      fail "Podman is installed but unavailable. Start its machine and retry."
    ;;
  nerdctl)
    require_command nerdctl "Install nerdctl, or unset KIND_EXPERIMENTAL_PROVIDER to use Docker."
    nerdctl info >/dev/null 2>&1 ||
      fail "nerdctl cannot reach its containerd service."
    ;;
  *)
    fail "Unsupported KIND_EXPERIMENTAL_PROVIDER='$CONTAINER_PROVIDER'. Expected docker, podman, or nerdctl."
    ;;
esac

info "Locating the Kind cluster that hosts the e-commerce app"
CONTEXT="$(find_ecommerce_context)"
kubectl config use-context "$CONTEXT" >/dev/null
kubectl cluster-info >/dev/null 2>&1 ||
  fail "Context '$CONTEXT' exists, but its Kubernetes API is unavailable."
printf 'Using context: %s\n' "$CONTEXT"

info "Validating observability manifests"
for manifest in "${MANIFESTS[@]}"; do
  [[ -f "$SCRIPT_DIR/$manifest" ]] ||
    fail "Required manifest is missing: $SCRIPT_DIR/$manifest"
  kubectl apply --dry-run=client -f "$SCRIPT_DIR/$manifest" >/dev/null
  printf 'Validated %s\n' "$manifest"
done

info "Applying observability manifests"
for manifest in "${MANIFESTS[@]}"; do
  kubectl apply -f "$SCRIPT_DIR/$manifest"
done

# Prometheus and Promtail read their ConfigMaps at process startup. Restarting
# these workloads makes configuration updates effective when this script is
# rerun.
kubectl rollout restart deployment/prometheus -n "$OBSERVABILITY_NAMESPACE"
kubectl rollout restart daemonset/promtail -n "$OBSERVABILITY_NAMESPACE"

info "Waiting for observability workloads"
kubectl rollout status deployment/prometheus -n "$OBSERVABILITY_NAMESPACE" --timeout="$TIMEOUT"
kubectl rollout status daemonset/node-exporter -n "$OBSERVABILITY_NAMESPACE" --timeout="$TIMEOUT"
kubectl rollout status deployment/loki -n "$OBSERVABILITY_NAMESPACE" --timeout="$TIMEOUT"
kubectl rollout status daemonset/promtail -n "$OBSERVABILITY_NAMESPACE" --timeout="$TIMEOUT"
kubectl rollout status deployment/grafana -n "$OBSERVABILITY_NAMESPACE" --timeout="$TIMEOUT"

info "Verifying resources"
kubectl get deployments,daemonsets,services,pods -n "$OBSERVABILITY_NAMESPACE" -o wide
kubectl get endpoints prometheus node-exporter loki grafana -n "$OBSERVABILITY_NAMESPACE"
for service in prometheus node-exporter loki grafana; do
  endpoint_addresses="$(
    kubectl get endpoints "$service" -n "$OBSERVABILITY_NAMESPACE" \
      -o jsonpath='{.subsets[*].addresses[*].ip}'
  )"
  [[ -n "$endpoint_addresses" ]] ||
    fail "Service '$service' has no ready endpoints. Inspect it with:
  kubectl --context $CONTEXT describe service/$service -n $OBSERVABILITY_NAMESPACE"
done

cat <<EOF

Observability is ready in context '$CONTEXT'.

Access (run each port-forward in its own terminal):
  kubectl --context $CONTEXT port-forward -n $OBSERVABILITY_NAMESPACE service/prometheus 9090:9090
  kubectl --context $CONTEXT port-forward -n $OBSERVABILITY_NAMESPACE service/loki 3100:3100
  kubectl --context $CONTEXT port-forward -n $OBSERVABILITY_NAMESPACE service/grafana 3001:3000

Open:
  Prometheus targets: http://localhost:9090/targets
  Grafana:            http://localhost:3001  (admin / admin)

Verify:
  kubectl --context $CONTEXT get pods -n $OBSERVABILITY_NAMESPACE
  kubectl --context $CONTEXT logs -n $OBSERVABILITY_NAMESPACE daemonset/promtail --tail=50
  kubectl --context $CONTEXT logs -n $OBSERVABILITY_NAMESPACE deployment/loki --tail=50
  curl -fsS http://localhost:3100/ready
  curl -sG http://localhost:3100/loki/api/v1/label/pod/values --data-urlencode 'query={namespace="ecommerce"}'
  curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=count by (app) (up{job="ecommerce-pods"} == 1)'
  curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=count by (node) (up{job="node-exporter"} == 1)'

Useful Loki query:
  {namespace="ecommerce", app="product-service"}
EOF

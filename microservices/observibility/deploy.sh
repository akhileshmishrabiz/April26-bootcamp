#!/bin/bash
#
# Spin up Kind cluster with Prometheus, Grafana, Loki, Promtail,
# and the e-commerce microservices stack.
#
# Usage:
#   ./deploy.sh              # Full stack (monitoring + app)
#   ./deploy.sh --monitoring-only
#   ./deploy.sh --skip-app     # Kind + monitoring only
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CNI_INSTALL_SCRIPT="${SCRIPT_DIR}/servicemesh-networkingpolicies/cni/install-cilium.sh"
CLUSTER_NAME="ecommerce-vault"
NAMESPACE="monitoring"
RELEASE_NAME="observability"
CHART_PATH="${SCRIPT_DIR}/monitoring"
APP_DEPLOY_SCRIPT="${SCRIPT_DIR}/../helm-deployments-kind/helm-ms-cnpg-vault-eso/helm-cnpg-vault-deploy.sh"

DEPLOY_APP=true
MONITORING_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --monitoring-only|--skip-app)
            DEPLOY_APP=false
            MONITORING_ONLY=true
            ;;
        --help|-h)
            echo "Usage: $0 [--monitoring-only|--skip-app]"
            exit 0
            ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_info() { echo -e "${YELLOW}INFO: $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ ERROR: $1${NC}"; exit 1; }

# Pin versions for reproducible local images
PROMETHEUS_VERSION="v2.51.2"
GRAFANA_VERSION="10.4.2"
LOKI_VERSION="2.9.6"
PROMTAIL_VERSION="2.9.6"
TEMPO_VERSION="2.4.1"
OTEL_COLLECTOR_VERSION="0.96.0"

# ============================================================
# STEP 0: Prerequisites
# ============================================================
print_step "0" "Checking Prerequisites"

for cmd in docker kind kubectl helm; do
    command -v "$cmd" >/dev/null 2>&1 || print_error "$cmd is not installed"
    print_success "$cmd found"
done

docker info >/dev/null 2>&1 || print_error "Docker is not running"
print_success "Docker is running"

# ============================================================
# STEP 1: Kind Cluster
# ============================================================
print_step "1" "Setting Up Kind Cluster"

CLUSTER_JUST_CREATED=false

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_info "Cluster '${CLUSTER_NAME}' already exists — reusing"
    kubectl config use-context "kind-${CLUSTER_NAME}"
else
    print_info "Creating cluster '${CLUSTER_NAME}' (disableDefaultCNI — Cilium will be installed next)..."
    kind create cluster --config "${SCRIPT_DIR}/kind-config.yaml" --name "${CLUSTER_NAME}"
    CLUSTER_JUST_CREATED=true
    print_success "Kind cluster created"
fi

# ============================================================
# STEP 1b: Cilium CNI + Hubble (NetworkPolicy enforcement + flow visibility)
# ============================================================
print_step "1b" "Installing Cilium CNI + Hubble"

if [ ! -x "${CNI_INSTALL_SCRIPT}" ]; then
    print_error "CNI install script not found: ${CNI_INSTALL_SCRIPT}"
fi

if [ "${CLUSTER_JUST_CREATED}" = true ]; then
    print_info "Fresh cluster — installing Cilium before any workloads..."
    bash "${CNI_INSTALL_SCRIPT}" --with-cluster
else
    if kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -q Running; then
        print_success "Cilium already running — skipping CNI install"
    elif kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep -q Running; then
        print_info "Cluster is using Calico — recreate for Cilium + Hubble:"
        print_info "  kind delete cluster --name ${CLUSTER_NAME} && ./deploy.sh"
    elif kubectl get pods -n kube-system -l app=kindnet --no-headers 2>/dev/null | grep -q Running; then
        print_info "Cluster is using kindnet — NetworkPolicies will NOT be enforced."
        print_info "Recreate for Cilium: kind delete cluster --name ${CLUSTER_NAME} && ./deploy.sh"
    else
        print_info "No CNI detected — attempting Cilium install..."
        bash "${CNI_INSTALL_SCRIPT}" --with-cluster || \
            print_info "CNI install skipped — see ${CNI_INSTALL_SCRIPT} --help"
    fi
    kubectl wait --for=condition=ready node --all --timeout=120s
fi

print_success "Cluster is ready"

# ============================================================
# STEP 2: Pull Monitoring Images (loaded locally into Kind)
# ============================================================
print_step "2" "Pulling Monitoring Images"

pull_image() {
    local img="$1"
    print_info "Pulling ${img}..."
    docker pull "${img}"
    print_success "${img} ready"
}

pull_image "prom/prometheus:${PROMETHEUS_VERSION}"
pull_image "grafana/grafana:${GRAFANA_VERSION}"
pull_image "grafana/loki:${LOKI_VERSION}"
pull_image "grafana/promtail:${PROMTAIL_VERSION}"
pull_image "grafana/tempo:${TEMPO_VERSION}"
pull_image "otel/opentelemetry-collector-contrib:${OTEL_COLLECTOR_VERSION}"

# ============================================================
# STEP 3: Load Images into Kind
# ============================================================
print_step "3" "Loading Monitoring Images into Kind"

load_image_into_kind() {
    local img="$1"
    print_info "Loading ${img} into Kind..."
    docker save "${img}" | docker exec -i "${CLUSTER_NAME}-control-plane" \
        ctr -n k8s.io images import -
    print_success "Loaded ${img}"
}

for img in \
    "prom/prometheus:${PROMETHEUS_VERSION}" \
    "grafana/grafana:${GRAFANA_VERSION}" \
    "grafana/loki:${LOKI_VERSION}" \
    "grafana/promtail:${PROMTAIL_VERSION}" \
    "grafana/tempo:${TEMPO_VERSION}" \
    "otel/opentelemetry-collector-contrib:${OTEL_COLLECTOR_VERSION}"; do
    load_image_into_kind "${img}"
done

# ============================================================
# STEP 4: Sync Dashboards into Helm Chart
# ============================================================
print_step "4" "Syncing Dashboards"

mkdir -p "${CHART_PATH}/dashboards"
cp "${SCRIPT_DIR}/dashboards/"*.json "${CHART_PATH}/dashboards/"
print_success "Dashboards synced to Helm chart"

# ============================================================
# STEP 5: Deploy Monitoring Stack via Helm
# ============================================================
print_step "5" "Deploying Monitoring Stack (Prometheus + Grafana + Loki + Promtail + Tempo + OTel)"

helm lint "${CHART_PATH}"
print_success "Helm chart is valid"

if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    print_info "Upgrading observability release..."
    helm upgrade "${RELEASE_NAME}" "${CHART_PATH}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --timeout 5m
else
    print_info "Installing observability release..."
    helm install "${RELEASE_NAME}" "${CHART_PATH}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --timeout 5m
fi

print_info "Waiting for Prometheus..."
kubectl wait --for=condition=available deployment/prometheus \
    -n "${NAMESPACE}" --timeout=180s

print_info "Waiting for Grafana..."
kubectl wait --for=condition=available deployment/grafana \
    -n "${NAMESPACE}" --timeout=180s

print_info "Waiting for Loki..."
kubectl wait --for=condition=available deployment/loki \
    -n "${NAMESPACE}" --timeout=180s

print_info "Waiting for Promtail..."
kubectl rollout status daemonset/promtail -n "${NAMESPACE}" --timeout=180s

print_info "Waiting for Tempo..."
kubectl wait --for=condition=available deployment/tempo \
    -n "${NAMESPACE}" --timeout=180s 2>/dev/null || print_info "Tempo may still be starting"

print_info "Waiting for OTel Collector..."
kubectl wait --for=condition=available deployment/otel-collector \
    -n "${NAMESPACE}" --timeout=180s 2>/dev/null || print_info "OTel Collector may still be starting"

print_success "Monitoring stack deployed"

# ============================================================
# STEP 6: Deploy E-Commerce App (optional)
# ============================================================
if [ "${DEPLOY_APP}" = true ]; then
    print_step "6" "Deploying E-Commerce Microservices"

    if [ ! -f "${APP_DEPLOY_SCRIPT}" ]; then
        print_error "App deploy script not found: ${APP_DEPLOY_SCRIPT}"
    fi

    print_info "Running ${APP_DEPLOY_SCRIPT}..."
    (cd "$(dirname "${APP_DEPLOY_SCRIPT}")" && bash "$(basename "${APP_DEPLOY_SCRIPT}")")
    print_success "E-commerce stack deployed"
else
    print_step "6" "Skipping E-Commerce App (--monitoring-only)"
fi

# ============================================================
# STEP 7: Verify & Print Access Info
# ============================================================
print_step "7" "Deployment Complete"

echo -e "${YELLOW}Monitoring Pods:${NC}"
kubectl get pods -n "${NAMESPACE}"

if [ "${DEPLOY_APP}" = true ]; then
    echo -e "\n${YELLOW}E-Commerce Pods:${NC}"
    kubectl get pods -n ecommerce 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  OBSERVABILITY STACK READY${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}Access URLs:${NC}"
echo "  Grafana:      http://localhost:3030   (admin / admin)"
echo "  Prometheus:   http://localhost:9090"
echo "  Loki:         http://localhost:3100   (query via Grafana)"
if [ "${DEPLOY_APP}" = true ]; then
    echo "  Frontend:     http://localhost:4000"
    echo "  API Gateway:  http://localhost:9080"
    echo "  Vault UI:     http://localhost:18200  (Token: root)"
    echo "  RabbitMQ UI:  http://localhost:16672"
    echo "  Mailpit UI:   http://localhost:8025"
fi
echo ""
echo -e "${YELLOW}Grafana Dashboards (folder: E-Commerce):${NC}"
echo "  - Microservices Overview      (HTTP metrics, latency, KPIs)"
echo "  - Latency & Errors            (p50/p95/p99, 4xx/5xx, error logs)"
echo "  - Tracing & Correlated Logs   (Tempo traces + Loki)"
echo "  - Microservices Logs Explorer (Loki search & volume)"
echo "  - Infrastructure              (Redis & RabbitMQ)"
echo ""
echo -e "${YELLOW}Generate traffic for dashboards:${NC}"
echo "  ${SCRIPT_DIR}/simulate-traffic.sh --once"
echo "  ${SCRIPT_DIR}/simulate-traffic.sh --duration 300 --rate 3"
echo "  ${SCRIPT_DIR}/load-test/run-load-test.sh --smoke   # k6 load test (see --load, --stress, --spike)"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  kubectl get pods -n monitoring"
echo "  kubectl logs -n monitoring deploy/prometheus"
echo "  kubectl logs -n monitoring deploy/grafana"
echo "  kubectl logs -n monitoring deploy/loki"
echo "  helm upgrade ${RELEASE_NAME} ${CHART_PATH} -n ${NAMESPACE}"
echo ""
echo -e "${YELLOW}NetworkPolicies (requires Cilium — installed in step 1b):${NC}"
echo "  ${SCRIPT_DIR}/servicemesh-networkingpolicies/network-policies/deploy-np.sh --apply"
echo ""
echo -e "${YELLOW}Hubble — view blocked traffic:${NC}"
echo "  http://localhost:12000                              # Hubble UI"
echo "  hubble observe --verdict DROPPED -n ecommerce -f  # CLI (brew install hubble)"
echo ""
echo -e "${YELLOW}Service Mesh + NetworkPolicies (optional, existing cluster):${NC}"
echo "  ${SCRIPT_DIR}/servicemesh-networkingpolicies/deploy.sh              # Linkerd + policies"
echo "  ${SCRIPT_DIR}/servicemesh-networkingpolicies/deploy.sh --mesh-only  # Linkerd only"
echo ""
echo -e "${YELLOW}Cleanup:${NC}"
echo "  helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
if [ "${DEPLOY_APP}" = true ]; then
    echo "  helm uninstall ecommerce-vault -n ecommerce"
    echo "  helm uninstall vault -n vault"
    echo "  helm uninstall external-secrets -n external-secrets"
fi
echo "  kind delete cluster --name ${CLUSTER_NAME}"
echo ""

# Quick health checks
print_info "Running health checks..."
sleep 3

if curl -sf --connect-timeout 3 http://localhost:9090/-/healthy >/dev/null 2>&1; then
    print_success "Prometheus is healthy"
else
    print_info "Prometheus may still be starting — try: curl http://localhost:9090/-/healthy"
fi

if curl -sf --connect-timeout 3 http://localhost:3030/api/health >/dev/null 2>&1; then
    print_success "Grafana is healthy"
else
    print_info "Grafana may still be starting — try: curl http://localhost:3030/api/health"
fi

if [ "${DEPLOY_APP}" = true ]; then
    if curl -sf --connect-timeout 3 http://localhost:9080/health 2>/dev/null | grep -q "OK"; then
        print_success "API Gateway is healthy"
    else
        print_info "API Gateway may still be starting"
    fi
fi

echo ""
print_success "Done!"

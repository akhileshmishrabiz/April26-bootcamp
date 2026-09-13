#!/bin/bash
#
# Install Linkerd service mesh + ecommerce NetworkPolicies on the existing
# ecommerce-vault Kind cluster (no cluster recreation).
#
# NetworkPolicies require an enforcing CNI (Cilium + Hubble). On Kind, kindnet does NOT
# enforce policies — install Cilium first via observibility/deploy.sh or:
#   servicemesh-networkingpolicies/cni/install-cilium.sh --with-cluster
#
# Usage:
#   ./deploy.sh                 # Linkerd (via install-linkerd.sh) + NetworkPolicies
#   ./deploy.sh --mesh-only     # Linkerd only — same as install-linkerd.sh
#   ./deploy.sh --policies-only # NetworkPolicies only (skip Linkerd)
#   ./deploy.sh --help
#

set -e

# Network policies disabled by default — set DISABLE_NP=0 to re-enable apply.
export DISABLE_NP="${DISABLE_NP:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="ecommerce-vault"
APP_NAMESPACE="ecommerce"
MONITORING_NAMESPACE="monitoring"
LINKERD_NAMESPACE="linkerd"
LINKERD_VIZ_NAMESPACE="linkerd-viz"

INSTALL_MESH=true
INSTALL_POLICIES=true

for arg in "$@"; do
    case "$arg" in
        --mesh-only)
            INSTALL_POLICIES=false
            ;;
        --policies-only)
            INSTALL_MESH=false
            ;;
        --help|-h)
            echo "Usage: $0 [--mesh-only|--policies-only]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--mesh-only|--policies-only]"
            exit 1
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

install_linkerd_mesh() {
    "${SCRIPT_DIR}/install-linkerd.sh"
}

install_network_policies() {
    print_step "4" "Applying NetworkPolicies (ecommerce namespace)"

    if [ "${DISABLE_NP:-0}" = "1" ]; then
        print_info "DISABLE_NP=1 — skipping NetworkPolicy apply (policies intentionally disabled)"
        return 0
    fi

    if ! kubectl get namespace "${APP_NAMESPACE}" >/dev/null 2>&1; then
        print_error "Namespace '${APP_NAMESPACE}' not found — deploy the app stack first"
    fi

    CNI_SCRIPT="${SCRIPT_DIR}/cni/install-cilium.sh"
    if ! kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -q Running; then
        if kubectl get pods -n kube-system -l app=kindnet --no-headers 2>/dev/null | grep -q Running; then
            print_error "kindnet active — NetworkPolicies are not enforced on Kind. Recreate cluster with Cilium: kind delete cluster --name ${CLUSTER_NAME} && cd ../ && ./deploy.sh"
        elif kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep -q Running; then
            print_error "Calico active — recreate cluster for Cilium + Hubble: kind delete cluster --name ${CLUSTER_NAME} && cd ../ && ./deploy.sh"
        elif [ -x "${CNI_SCRIPT}" ]; then
            print_info "Cilium not found — install CNI before policies can enforce traffic"
            print_info "Run: ${CNI_SCRIPT} --with-cluster  (or recreate cluster via observibility/deploy.sh)"
            print_error "Aborting policy apply — CNI prerequisite not met"
        fi
    fi

    kubectl apply -f "${SCRIPT_DIR}/network-policies/"
    print_success "NetworkPolicies applied"
}

# ============================================================
# STEP 0: Prerequisites
# ============================================================
print_step "0" "Checking Prerequisites"

for cmd in docker kubectl helm openssl; do
    command -v "$cmd" >/dev/null 2>&1 || print_error "$cmd is not installed"
    print_success "$cmd found"
done

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_error "Kind cluster '${CLUSTER_NAME}' not found. Run observibility/deploy.sh first."
fi

kubectl config use-context "kind-${CLUSTER_NAME}"
kubectl cluster-info >/dev/null 2>&1 || print_error "Cannot reach cluster '${CLUSTER_NAME}'"
print_success "Using cluster kind-${CLUSTER_NAME}"

if [ "${INSTALL_MESH}" = true ]; then
    install_linkerd_mesh
fi

if [ "${INSTALL_POLICIES}" = true ]; then
    install_network_policies
fi

# ============================================================
# Summary
# ============================================================
print_step "5" "Linkerd + NetworkPolicy Deployment Complete"

echo -e "${YELLOW}Linkerd pods:${NC}"
kubectl get pods -n "${LINKERD_NAMESPACE}" 2>/dev/null || true
kubectl get pods -n "${LINKERD_VIZ_NAMESPACE}" 2>/dev/null || true

echo -e "\n${YELLOW}NetworkPolicies in ${APP_NAMESPACE}:${NC}"
kubectl get networkpolicy -n "${APP_NAMESPACE}" 2>/dev/null || true

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  LINKERD + NETWORK POLICIES READY${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}What was enforced:${NC}"
echo "  • Linkerd mTLS between meshed pods in ${APP_NAMESPACE} (automatic for injected proxies)"
echo "  • Linkerd Server CRs for HTTP protocol detection on microservice ports"
echo "  • Optional strict AuthorizationPolicy: mesh/server-authorization/authorization-policies.strict.yaml"
echo "  • default-deny-all baseline + explicit allow rules for DNS, gateway, services"
echo "  • Redis/RabbitMQ/Postgres restricted to authorized callers"
echo "  • Prometheus scrape + OTel export from ${MONITORING_NAMESPACE}"
echo ""
echo -e "${YELLOW}Access:${NC}"
echo "  Linkerd Viz dashboard (service map, golden metrics, tap):"
echo "    http://localhost:8084"
echo "    kubectl -n ${LINKERD_VIZ_NAMESPACE} port-forward svc/web 8084:8084"
echo ""
echo "  Grafana Linkerd Golden Metrics dashboard:"
echo "    http://localhost:3030  (folder: E-Commerce → Linkerd Golden Metrics)"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  ${SCRIPT_DIR}/install-linkerd.sh          # Linkerd mesh + Viz (primary)"
echo "  ${SCRIPT_DIR}/deploy.sh --policies-only   # re-apply NetworkPolicies only"
echo "  ${SCRIPT_DIR}/deploy.sh --mesh-only       # same as install-linkerd.sh"
if command -v linkerd >/dev/null 2>&1; then
    echo "  linkerd check"
    echo "  linkerd viz stat deploy -n ${APP_NAMESPACE}"
else
    echo "  (optional) install linkerd CLI for: linkerd check / linkerd viz stat"
fi
echo ""
echo -e "${YELLOW}Hubble (Cilium — policy drops / flows):${NC}"
echo "  http://localhost:12000"
echo "  hubble observe --verdict DROPPED -n ${APP_NAMESPACE} -f"
echo ""
echo -e "${YELLOW}Kind caveats:${NC}"
echo "  • Cilium CNI must be installed for NetworkPolicies + Hubble (observibility/deploy.sh step 1b)"
echo "  • Apply AFTER the app stack is running; policies are additive on existing cluster"
echo "  • NodePort ingress uses broad allow rules — Kind source IPs are not pod CIDRs"
echo "  • If pods fail after injection, check: kubectl describe pod -n ${APP_NAMESPACE} <name>"
echo "  • CNPG/RabbitMQ/Redis are meshed — if a datastore fails probes, annotate with"
echo "    config.linkerd.io/skip-inbound-ports or config.linkerd.io/skip-outbound-ports"
echo "  • Vault/ESO run outside ${APP_NAMESPACE}; app pods use synced K8s Secrets (no Vault egress needed)"
echo "  • Delete mesh: helm uninstall linkerd-viz -n ${LINKERD_VIZ_NAMESPACE}; helm uninstall linkerd-control-plane linkerd-crds -n ${LINKERD_NAMESPACE}"
echo "  • Delete policies: kubectl delete networkpolicy -l app.kubernetes.io/part-of=ecommerce-network-policy -n ${APP_NAMESPACE}"
echo ""
print_success "Done!"

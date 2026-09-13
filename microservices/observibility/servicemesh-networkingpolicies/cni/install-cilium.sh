#!/bin/bash
#
# Install Cilium CNI + Hubble on the ecommerce-vault Kind cluster.
# Cilium enforces NetworkPolicies; Hubble visualizes flows and policy drops.
#
# Usage:
#   ./install-cilium.sh                  # install (warns if kindnet/calico active)
#   ./install-cilium.sh --with-cluster   # fresh cluster path (called by observibility/deploy.sh)
#   ./install-cilium.sh --skip-cni-check # skip migration warning
#   ./install-cilium.sh --help
#
# Prerequisites:
#   - helm, kubectl, docker, kind
#   - kind cluster with disableDefaultCNI: true and podSubnet: 192.168.0.0/16
#   - Run BEFORE deploying workloads (nodes stay NotReady until CNI is up)
#
# Migrating from Calico/kindnet — recreate the cluster:
#   kind delete cluster --name ecommerce-vault
#   cd ../../ && ./deploy.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="ecommerce-vault"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
CILIUM_VERSION="1.16.5"
VALUES_FILE="${SCRIPT_DIR}/cilium-kind-values.yaml"

WITH_CLUSTER=false
SKIP_CNI_CHECK=false

for arg in "$@"; do
    case "$arg" in
        --with-cluster)     WITH_CLUSTER=true ;;
        --skip-cni-check)   SKIP_CNI_CHECK=true ;;
        --help|-h)
            sed -n '2,22p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--with-cluster|--skip-cni-check|--help]"
            exit 1
            ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${YELLOW}INFO:${NC} $*"; }
print_success() { echo -e "${GREEN}✓${NC} $*"; }
print_warn()    { echo -e "${YELLOW}WARN:${NC} $*"; }
print_error()   { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

echo -e "${BLUE}Cilium CNI + Hubble install (Kind + NetworkPolicy enforcement)${NC}\n"

print_info "CNI comparison:"
echo "  kindnet  — Kind default; NetworkPolicies accepted but NOT enforced."
echo "  Calico   — iptables enforcement; no Hubble flow UI."
echo "  Cilium   — eBPF enforcement + Hubble for live flows and DROPPED verdicts."
echo ""

for cmd in docker kubectl helm; do
    command -v "$cmd" >/dev/null 2>&1 || print_error "$cmd is not installed"
done

[ -f "${VALUES_FILE}" ] || print_error "Values file not found: ${VALUES_FILE}"

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_error "Kind cluster '${CLUSTER_NAME}' not found. Run: cd ../../ && ./deploy.sh"
fi

if ! kubectl config get-contexts -o name 2>/dev/null | grep -q "^${KUBECTL_CONTEXT}$"; then
    print_error "Context '${KUBECTL_CONTEXT}' not found"
fi

kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null
print_success "Using context ${KUBECTL_CONTEXT}"

print_hubble_access() {
    print_info "Hubble — observe blocked traffic:"
    echo "  brew install hubble   # macOS CLI (optional)"
    echo "  hubble status"
    echo "  hubble observe --verdict DROPPED -n ecommerce -f"
    echo ""
    print_info "Hubble UI:"
    echo "  http://localhost:12000   (Kind port mapping from kind-config.yaml)"
    echo "  kubectl -n kube-system port-forward svc/hubble-ui 12000:80"
    echo ""
    print_info "Apply NetworkPolicies:"
    echo "  ${SCRIPT_DIR}/../network-policies/deploy-np.sh --apply"
}

# --- Detect existing CNI ---
KINDNET_RUNNING=false
CALICO_RUNNING=false
CILIUM_RUNNING=false

if kubectl get pods -n kube-system -l app=kindnet --no-headers 2>/dev/null | grep -q Running; then
    KINDNET_RUNNING=true
fi
if kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep -q Running; then
    CALICO_RUNNING=true
fi
if kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -q Running; then
    CILIUM_RUNNING=true
fi

if [ "${CILIUM_RUNNING}" = true ]; then
    print_success "Cilium is already running — skipping install"
    kubectl get pods -n kube-system -l 'k8s-app in (cilium,hubble-relay)' 2>/dev/null || true
    echo ""
    print_hubble_access
    exit 0
fi

if { [ "${KINDNET_RUNNING}" = true ] || [ "${CALICO_RUNNING}" = true ]; } \
    && [ "${WITH_CLUSTER}" = false ] && [ "${SKIP_CNI_CHECK}" = false ]; then
    echo -e "${RED}Cannot install Cilium on a cluster with an active CNI (kindnet/Calico).${NC}"
    echo ""
    [ "${CALICO_RUNNING}" = true ] && print_warn "Calico is running — must recreate cluster to switch to Cilium."
    [ "${KINDNET_RUNNING}" = true ] && print_warn "kindnet is running — cluster needs disableDefaultCNI: true at create time."
    echo ""
    echo -e "${YELLOW}Recreate the cluster with Cilium:${NC}"
    echo "  kind delete cluster --name ${CLUSTER_NAME}"
    echo "  cd $(cd "${SCRIPT_DIR}/../.." && pwd) && ./deploy.sh"
    echo ""
    print_info "To attempt install anyway (not recommended): $0 --skip-cni-check"
    exit 1
fi

# --- Resolve image tags from Helm chart ---
print_info "Adding Cilium Helm repo..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium >/dev/null

CILIUM_IMAGES=(
    "quay.io/cilium/cilium:v${CILIUM_VERSION}"
    "quay.io/cilium/operator-generic:v${CILIUM_VERSION}"
    "quay.io/cilium/hubble-relay:v${CILIUM_VERSION}"
)

# Hubble UI images (version bundled with Cilium 1.16.x chart)
HUBBLE_UI_TAG="0.13.1"
CILIUM_IMAGES+=(
    "quay.io/cilium/hubble-ui:v${HUBBLE_UI_TAG}"
    "quay.io/cilium/hubble-ui-backend:v${HUBBLE_UI_TAG}"
)

load_image_into_kind() {
    local img="$1"
    local short_name="${img##*/}"
    if docker exec "${CLUSTER_NAME}-control-plane" ctr -n k8s.io images ls -q 2>/dev/null | grep -q "${short_name%%:*}"; then
        print_info "Skipping ${img} (already in Kind)"
        return
    fi
    print_info "Pulling ${img}..."
    docker pull "${img}"
    print_info "Loading ${img} into Kind..."
    docker save "${img}" | docker exec -i "${CLUSTER_NAME}-control-plane" \
        ctr -n k8s.io images import -
    print_success "Loaded ${img}"
}

echo ""
print_info "Loading Cilium ${CILIUM_VERSION} images into Kind..."
for img in "${CILIUM_IMAGES[@]}"; do
    load_image_into_kind "${img}"
done

print_info "Installing Cilium ${CILIUM_VERSION} via Helm..."
if helm status cilium -n kube-system >/dev/null 2>&1; then
    helm upgrade cilium cilium/cilium \
        --version "${CILIUM_VERSION}" \
        --namespace kube-system \
        -f "${VALUES_FILE}" \
        --timeout 10m
else
    helm install cilium cilium/cilium \
        --version "${CILIUM_VERSION}" \
        --namespace kube-system \
        -f "${VALUES_FILE}" \
        --timeout 10m
fi

print_info "Waiting for Cilium DaemonSet..."
kubectl rollout status daemonset/cilium -n kube-system --timeout=300s

print_info "Waiting for Cilium operator..."
kubectl wait --for=condition=available deployment/cilium-operator \
    -n kube-system --timeout=180s 2>/dev/null || \
    kubectl wait --for=condition=available deployment/cilium-operator-generic \
        -n kube-system --timeout=180s

print_info "Waiting for Hubble Relay..."
kubectl wait --for=condition=available deployment/hubble-relay \
    -n kube-system --timeout=180s 2>/dev/null || \
    print_warn "hubble-relay not ready yet — check: kubectl get pods -n kube-system -l k8s-app=hubble-relay"

print_info "Waiting for Hubble UI..."
kubectl wait --for=condition=available deployment/hubble-ui \
    -n kube-system --timeout=180s 2>/dev/null || \
    print_warn "hubble-ui not ready yet — check: kubectl get pods -n kube-system -l k8s-app=hubble-ui"

print_info "Waiting for nodes to become Ready..."
kubectl wait --for=condition=ready node --all --timeout=180s

echo ""
print_success "Cilium ${CILIUM_VERSION} + Hubble installed"
echo ""
kubectl get pods -n kube-system -l 'k8s-app in (cilium,hubble-relay,hubble-ui)' 2>/dev/null || \
    kubectl get pods -n kube-system | grep -E 'cilium|hubble' || true
echo ""
print_hubble_access

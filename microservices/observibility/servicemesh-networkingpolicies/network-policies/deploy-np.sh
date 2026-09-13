#!/bin/bash
#
# Deploy Kubernetes NetworkPolicies ONLY on the existing ecommerce-vault cluster.
# Does NOT install Linkerd, does NOT apply mesh/ Server or AuthorizationPolicy CRs.
#
# Usage:
#   ./deploy-np.sh              # validate manifests + show what would be applied (no changes)
#   ./deploy-np.sh --apply      # apply NetworkPolicies to the cluster
#   ./deploy-np.sh --delete     # remove all NetworkPolicies from this folder
#   ./deploy-np.sh --status     # list current NetworkPolicies in ecommerce namespace
#   ./deploy-np.sh --help
#
# Skip apply (policies disabled on cluster):
#   DISABLE_NP=1 ./deploy-np.sh --apply
#

set -euo pipefail

# Policies disabled by default — set DISABLE_NP=0 to re-enable apply.
export DISABLE_NP="${DISABLE_NP:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="ecommerce-vault"
APP_NAMESPACE="ecommerce"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"

DO_APPLY=false
DO_DELETE=false
DO_STATUS=false

for arg in "$@"; do
    case "$arg" in
        --apply)   DO_APPLY=true ;;
        --delete)  DO_DELETE=true ;;
        --status)  DO_STATUS=true ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--apply|--delete|--status|--help]"
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
print_error()   { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

echo -e "${BLUE}NetworkPolicy deploy (Kubernetes only — no service mesh policies)${NC}\n"

command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"

if ! kubectl config get-contexts -o name 2>/dev/null | grep -q "^${KUBECTL_CONTEXT}$"; then
    print_error "Context '${KUBECTL_CONTEXT}' not found. Run: cd ../../ && ./deploy.sh"
fi

kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null
print_success "Using context ${KUBECTL_CONTEXT}"

if ! kubectl get namespace "${APP_NAMESPACE}" >/dev/null 2>&1; then
    print_error "Namespace '${APP_NAMESPACE}' not found — deploy the app stack first (observibility/deploy.sh)"
fi

MANIFESTS=("${SCRIPT_DIR}"/*.yaml)
if [ ! -f "${MANIFESTS[0]}" ]; then
    print_error "No NetworkPolicy YAML files found in ${SCRIPT_DIR}"
fi

print_info "Manifests in scope ($((${#MANIFESTS[@]})) files):"
for f in "${MANIFESTS[@]}"; do
    echo "  - $(basename "$f")"
done
echo ""

print_info "Validating manifests (client dry-run)..."
kubectl apply --dry-run=client -f "${SCRIPT_DIR}/" >/dev/null
print_success "All manifests are valid"

if [ "${DO_STATUS}" = true ]; then
    echo ""
    print_info "NetworkPolicies in namespace ${APP_NAMESPACE}:"
    kubectl get networkpolicy -n "${APP_NAMESPACE}" -l app.kubernetes.io/part-of=ecommerce-network-policy 2>/dev/null \
        || kubectl get networkpolicy -n "${APP_NAMESPACE}" 2>/dev/null \
        || echo "  (none)"
    exit 0
fi

if [ "${DO_DELETE}" = true ]; then
    print_info "Deleting NetworkPolicies from ${SCRIPT_DIR}..."
    kubectl delete -f "${SCRIPT_DIR}/" --ignore-not-found
    print_success "NetworkPolicies removed from ${APP_NAMESPACE}"
    exit 0
fi

if [ "${DO_APPLY}" = true ]; then
    if [ "${DISABLE_NP:-0}" = "1" ]; then
        print_info "DISABLE_NP=1 — skipping NetworkPolicy apply (policies intentionally disabled)"
        exit 0
    fi
    print_info "Applying NetworkPolicies to namespace ${APP_NAMESPACE}..."
    kubectl apply -f "${SCRIPT_DIR}/"
    print_success "NetworkPolicies applied"
    echo ""
    kubectl get networkpolicy -n "${APP_NAMESPACE}"
    echo ""
    print_info "Verify app still reachable:"
    echo "  curl http://localhost:9080/health"
    echo "  curl http://localhost:4000"
else
    echo ""
    print_info "Dry-run only — no policies were applied to the cluster."
    echo ""
    kubectl apply --dry-run=server -f "${SCRIPT_DIR}/" 2>/dev/null || \
        kubectl apply --dry-run=client -f "${SCRIPT_DIR}/"
    echo ""
    echo -e "${YELLOW}To apply NetworkPolicies to the cluster:${NC}"
    echo "  ${SCRIPT_DIR}/deploy-np.sh --apply"
    echo ""
    echo -e "${YELLOW}To remove after applying:${NC}"
    echo "  ${SCRIPT_DIR}/deploy-np.sh --delete"
fi

#!/bin/bash
#
# Install Linkerd service mesh + Viz on the existing ecommerce-vault Kind cluster.
# Mesh-only entry point — does NOT apply NetworkPolicies (use deploy-np.sh or deploy.sh --policies-only).
#
# Usage:
#   ./install-linkerd.sh                 # Full mesh + Viz + mesh policies + workload restart
#   ./install-linkerd.sh --skip-viz      # Control plane + mesh policies only
#   ./install-linkerd.sh --skip-restart  # Skip rollout restart (no proxy injection yet)
#   ./install-linkerd.sh --help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="ecommerce-vault"
APP_NAMESPACE="ecommerce"
MONITORING_NAMESPACE="monitoring"
LINKERD_NAMESPACE="linkerd"
LINKERD_VIZ_NAMESPACE="linkerd-viz"
LINKERD_VERSION="stable-2.14.10"
PROXY_INIT_VERSION="v2.2.3"
CERT_DIR="${SCRIPT_DIR}/.certs"
VIZ_PORT=8084

SKIP_VIZ=false
SKIP_RESTART=false

for arg in "$@"; do
    case "$arg" in
        --skip-viz)
            SKIP_VIZ=true
            ;;
        --skip-restart)
            SKIP_RESTART=true
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [--skip-viz] [--skip-restart] [--help]

Install Linkerd control plane, CNI plugin, Viz (optional), mesh policies, and restart
ecommerce workloads for proxy injection on the ecommerce-vault Kind cluster.

Options:
  --skip-viz       Skip Linkerd Viz dashboard install
  --skip-restart   Skip rollout restart of ecommerce Deployments/StatefulSets
  --help           Show this help

NetworkPolicies are NOT applied by this script. Use:
  network-policies/deploy-np.sh --apply
  deploy.sh --policies-only
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Run $0 --help for usage."
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
print_warn() { echo -e "${YELLOW}⚠ WARNING: $1${NC}"; }
print_error() { echo -e "${RED}✗ ERROR: $1${NC}"; exit 1; }

load_image_into_kind() {
    local img="$1"
    if docker exec "${CLUSTER_NAME}-control-plane" ctr -n k8s.io images ls -q | grep -q "${img##*/}" 2>/dev/null; then
        print_info "Skipping ${img} (already in Kind)"
        return
    fi
    print_info "Loading ${img} into Kind..."
    docker pull "${img}"
    docker save "${img}" | docker exec -i "${CLUSTER_NAME}-control-plane" \
        ctr -n k8s.io images import -
    print_success "Loaded ${img}"
}

issuer_cert_valid() {
    [ -f "${CERT_DIR}/ca.crt" ] && [ -f "${CERT_DIR}/issuer.crt" ] && [ -f "${CERT_DIR}/issuer.key" ] || return 1
    openssl x509 -in "${CERT_DIR}/issuer.crt" -noout -text 2>/dev/null | grep -q "CA:TRUE" || return 1
    # Linkerd identity signs proxy CSRs with ECDSA — issuer key MUST be ECDSA P-256 (not RSA).
    openssl x509 -in "${CERT_DIR}/issuer.crt" -noout -text 2>/dev/null | grep -q "Public Key Algorithm: id-ecPublicKey" || return 1
    return 0
}

generate_linkerd_certs() {
    mkdir -p "${CERT_DIR}"

    if issuer_cert_valid; then
        print_info "Reusing existing Linkerd identity certs in ${CERT_DIR}"
        return
    fi

    if [ -f "${CERT_DIR}/issuer.crt" ]; then
        print_info "Existing issuer cert invalid or not ECDSA — regenerating..."
        rm -f "${CERT_DIR}"/*
    fi

    print_info "Generating Linkerd trust anchor and issuer certificates (ECDSA P-256)..."

    cat > "${CERT_DIR}/openssl.cnf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
CN = root.linkerd.cluster.local

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash

[v3_intermediate_ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

    openssl ecparam -name prime256v1 -genkey -noout -out "${CERT_DIR}/ca.key"
    openssl req -x509 -new -sha256 -days 3650 \
        -key "${CERT_DIR}/ca.key" -out "${CERT_DIR}/ca.crt" \
        -config "${CERT_DIR}/openssl.cnf" -extensions v3_ca

    openssl ecparam -name prime256v1 -genkey -noout -out "${CERT_DIR}/issuer.key"
    openssl req -new \
        -key "${CERT_DIR}/issuer.key" -out "${CERT_DIR}/issuer.csr" \
        -subj "/CN=identity.linkerd.cluster.local"

    openssl x509 -req -in "${CERT_DIR}/issuer.csr" \
        -CA "${CERT_DIR}/ca.crt" -CAkey "${CERT_DIR}/ca.key" -CAcreateserial \
        -out "${CERT_DIR}/issuer.crt" -days 365 -sha256 \
        -extfile "${CERT_DIR}/openssl.cnf" -extensions v3_intermediate_ca

    print_success "Linkerd certificates generated (ECDSA P-256 issuer)"
}

check_cilium() {
    if kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -q Running; then
        print_success "Cilium CNI is running"
        return 0
    fi
    print_warn "Cilium is not running — Linkerd mesh can install, but NetworkPolicy enforcement requires Cilium."
    print_warn "Install Cilium: ${SCRIPT_DIR}/cni/install-cilium.sh --with-cluster"
    print_warn "Or recreate cluster: cd $(dirname "${SCRIPT_DIR}") && ./deploy.sh"
    return 1
}

maybe_start_viz_port_forward() {
    local pf_cmd="kubectl -n ${LINKERD_VIZ_NAMESPACE} port-forward svc/web ${VIZ_PORT}:${VIZ_PORT}"
    if ! curl -sf "http://localhost:${VIZ_PORT}/" >/dev/null 2>&1; then
        if ! lsof -i ":${VIZ_PORT}" >/dev/null 2>&1; then
            print_info "Starting Linkerd Viz port-forward in background..."
            nohup ${pf_cmd} >/tmp/linkerd-viz-pf.log 2>&1 &
            sleep 2
            if curl -sf "http://localhost:${VIZ_PORT}/" >/dev/null 2>&1; then
                print_success "Linkerd Viz available at http://localhost:${VIZ_PORT}"
                return
            fi
            print_warn "Port-forward started but dashboard not yet reachable — check /tmp/linkerd-viz-pf.log"
            return
        fi
    else
        print_success "Linkerd Viz already reachable at http://localhost:${VIZ_PORT}"
        return
    fi
    print_info "Start port-forward manually: ${pf_cmd}"
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

if ! kubectl get namespace "${APP_NAMESPACE}" >/dev/null 2>&1; then
    print_error "Namespace '${APP_NAMESPACE}' not found — deploy the app stack first (observibility/deploy.sh)"
fi
print_success "Namespace '${APP_NAMESPACE}' exists"

check_cilium || true

# ============================================================
# STEP 1: Load Linkerd images into Kind
# ============================================================
print_step "1" "Loading Linkerd Images into Kind"

helm repo add linkerd https://helm.linkerd.io/stable 2>/dev/null || true
helm repo update linkerd

LINKERD_IMAGES=(
    "cr.l5d.io/linkerd/controller:${LINKERD_VERSION}"
    "cr.l5d.io/linkerd/proxy:${LINKERD_VERSION}"
    "cr.l5d.io/linkerd/proxy-init:${PROXY_INIT_VERSION}"
    "cr.l5d.io/linkerd/cni-plugin:${LINKERD_VERSION}"
    "cr.l5d.io/linkerd/policy-controller:${LINKERD_VERSION}"
    "cr.l5d.io/linkerd/metrics-api:${LINKERD_VERSION}"
    "cr.l5d.io/linkerd/tap:${LINKERD_VERSION}"
    "cr.l5d.io/linkerd/web:${LINKERD_VERSION}"
)

for img in "${LINKERD_IMAGES[@]}"; do
    load_image_into_kind "${img}"
done

# ============================================================
# STEP 2: Generate identity certificates
# ============================================================
print_step "2" "Generating Linkerd Identity Certificates"

generate_linkerd_certs

print_info "Validating Linkerd Helm charts (helm template)..."
helm template test-crds linkerd/linkerd-crds >/dev/null
helm template test-cp linkerd/linkerd-control-plane -f "${SCRIPT_DIR}/values.yaml" \
    --set-file identityTrustAnchorsPEM="${CERT_DIR}/ca.crt" \
    --set-file identity.issuer.tls.crtPEM="${CERT_DIR}/issuer.crt" \
    --set-file identity.issuer.tls.keyPEM="${CERT_DIR}/issuer.key" >/dev/null
if [ "${SKIP_VIZ}" = false ]; then
    helm template test-viz linkerd/linkerd-viz -f "${SCRIPT_DIR}/values-viz.yaml" >/dev/null
fi
print_success "Helm charts valid"

# ============================================================
# STEP 3: Install Linkerd CRDs
# ============================================================
print_step "3" "Installing Linkerd CRDs"

if helm status linkerd-crds -n "${LINKERD_NAMESPACE}" >/dev/null 2>&1; then
    print_info "Upgrading linkerd-crds..."
    helm upgrade linkerd-crds linkerd/linkerd-crds -n "${LINKERD_NAMESPACE}" --timeout 5m
else
    print_info "Installing linkerd-crds..."
    helm install linkerd-crds linkerd/linkerd-crds -n "${LINKERD_NAMESPACE}" --create-namespace --timeout 5m
fi

kubectl wait --for=condition=Established crd/serverauthorizations.policy.linkerd.io --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=Established crd/servers.policy.linkerd.io --timeout=120s 2>/dev/null || true
print_success "Linkerd CRDs ready"

# ============================================================
# STEP 4–5: Linkerd CNI (before control plane — required with Cilium)
# ============================================================
print_step "4" "Installing Linkerd CNI Plugin"

print_info "Installing Linkerd CNI plugin (privileged=true, required with Cilium)..."
if helm status linkerd-cni -n "${LINKERD_NAMESPACE}" >/dev/null 2>&1; then
    helm upgrade linkerd-cni linkerd/linkerd2-cni \
        -n "${LINKERD_NAMESPACE}" \
        --set privileged=true \
        --set destCNINetDir=/etc/cni/net.d \
        --set destCNIBinDir=/opt/cni/bin \
        --timeout 5m
else
    helm install linkerd-cni linkerd/linkerd2-cni \
        -n "${LINKERD_NAMESPACE}" \
        --set privileged=true \
        --set destCNINetDir=/etc/cni/net.d \
        --set destCNIBinDir=/opt/cni/bin \
        --timeout 5m
fi

print_step "5" "Waiting for Linkerd CNI DaemonSet"
kubectl rollout status daemonset/linkerd-cni -n "${LINKERD_NAMESPACE}" --timeout=180s
print_success "Linkerd CNI plugin ready"

# ============================================================
# STEP 6–7: Control plane
# ============================================================
print_step "6" "Installing Linkerd Control Plane"

if helm status linkerd-control-plane -n "${LINKERD_NAMESPACE}" >/dev/null 2>&1; then
    print_info "Upgrading linkerd-control-plane..."
    helm upgrade linkerd-control-plane linkerd/linkerd-control-plane \
        -n "${LINKERD_NAMESPACE}" \
        -f "${SCRIPT_DIR}/values.yaml" \
        --set-file identityTrustAnchorsPEM="${CERT_DIR}/ca.crt" \
        --set-file identity.issuer.tls.crtPEM="${CERT_DIR}/issuer.crt" \
        --set-file identity.issuer.tls.keyPEM="${CERT_DIR}/issuer.key" \
        --timeout 5m
else
    print_info "Installing linkerd-control-plane..."
    helm install linkerd-control-plane linkerd/linkerd-control-plane \
        -n "${LINKERD_NAMESPACE}" \
        -f "${SCRIPT_DIR}/values.yaml" \
        --set-file identityTrustAnchorsPEM="${CERT_DIR}/ca.crt" \
        --set-file identity.issuer.tls.crtPEM="${CERT_DIR}/issuer.crt" \
        --set-file identity.issuer.tls.keyPEM="${CERT_DIR}/issuer.key" \
        --timeout 5m
fi

print_step "7" "Waiting for Linkerd Control Plane"
print_info "Waiting for Linkerd control plane deployments..."
kubectl wait --for=condition=available deployment/linkerd-destination \
    -n "${LINKERD_NAMESPACE}" --timeout=180s
kubectl wait --for=condition=available deployment/linkerd-identity \
    -n "${LINKERD_NAMESPACE}" --timeout=180s
kubectl wait --for=condition=available deployment/linkerd-proxy-injector \
    -n "${LINKERD_NAMESPACE}" --timeout=180s
print_success "Linkerd control plane ready"

# ============================================================
# STEP 8: Linkerd Viz
# ============================================================
if [ "${SKIP_VIZ}" = false ]; then
    print_step "8" "Installing Linkerd Viz"

    if helm status linkerd-viz -n "${LINKERD_VIZ_NAMESPACE}" >/dev/null 2>&1; then
        helm upgrade linkerd-viz linkerd/linkerd-viz \
            -n "${LINKERD_VIZ_NAMESPACE}" \
            -f "${SCRIPT_DIR}/values-viz.yaml" \
            --timeout 5m
    else
        helm install linkerd-viz linkerd/linkerd-viz \
            -n "${LINKERD_VIZ_NAMESPACE}" \
            --create-namespace \
            -f "${SCRIPT_DIR}/values-viz.yaml" \
            --timeout 5m
    fi

    kubectl wait --for=condition=available deployment/web \
        -n "${LINKERD_VIZ_NAMESPACE}" --timeout=180s
    print_success "Linkerd Viz ready"
else
    print_info "Skipping Linkerd Viz (--skip-viz)"
fi

# ============================================================
# STEP 9: Enable Prometheus scrape of linkerd-viz metrics-api
# ============================================================
print_step "9" "Enabling Linkerd Metrics in Observability Stack"

OBS_CHART="${SCRIPT_DIR}/../monitoring"
if helm status observability -n "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then
    print_info "Enabling Linkerd metrics scrape in observability stack..."
    helm upgrade observability "${OBS_CHART}" \
        -n "${MONITORING_NAMESPACE}" \
        --reuse-values \
        --set linkerdViz.enabled=true \
        --timeout 5m
    print_success "Prometheus now scrapes linkerd-viz metrics-api"
else
    print_warn "Helm release 'observability' not found — skip Prometheus Linkerd scrape (deploy monitoring first)"
fi

# ============================================================
# STEP 10: Mesh manifests
# ============================================================
print_step "10" "Applying Mesh Policies and Injection Annotations"

kubectl apply -f "${SCRIPT_DIR}/mesh/namespace-annotation.yaml"
kubectl apply -f "${SCRIPT_DIR}/mesh/cnpg-skip-injection.yaml"
kubectl apply -f "${SCRIPT_DIR}/mesh/redis-skip-ports.yaml"
kubectl apply -f "${SCRIPT_DIR}/mesh/server-authorization/meshed-auth.yaml"
kubectl apply -f "${SCRIPT_DIR}/mesh/server-authorization/servers.yaml"
kubectl apply -f "${SCRIPT_DIR}/mesh/server-authorization/authorization-policies.strict.yaml"
kubectl apply -f "${SCRIPT_DIR}/mesh/server-authorization/allow-prometheus-network-scrape.yaml"
kubectl apply -f "${SCRIPT_DIR}/mesh/retry-timeout/service-profiles.yaml"
print_success "Mesh policies applied"

# ============================================================
# STEP 11: Restart workloads for proxy injection
# ============================================================
if [ "${SKIP_RESTART}" = false ]; then
    print_step "11" "Restarting Ecommerce Workloads for Proxy Injection"

    print_info "Restarting ecommerce Deployments/StatefulSets to inject Linkerd proxies..."
    for kind in deployment statefulset; do
        for name in $(kubectl get "${kind}" -n "${APP_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            kubectl rollout restart "${kind}/${name}" -n "${APP_NAMESPACE}"
        done
    done

    print_info "Waiting for rollouts (meshed pods)..."
    kubectl rollout status deployment -n "${APP_NAMESPACE}" --timeout=600s 2>/dev/null || true
    kubectl rollout status statefulset -n "${APP_NAMESPACE}" --timeout=600s 2>/dev/null || true
    print_success "Ecommerce workloads restarted with Linkerd injection"
else
    print_info "Skipping workload restart (--skip-restart)"
fi

# ============================================================
# STEP 12–13: Access URLs and port-forward
# ============================================================
print_step "12" "Linkerd Mesh Install Complete"

echo -e "${YELLOW}Linkerd pods:${NC}"
kubectl get pods -n "${LINKERD_NAMESPACE}" 2>/dev/null || true
if [ "${SKIP_VIZ}" = false ]; then
    kubectl get pods -n "${LINKERD_VIZ_NAMESPACE}" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  LINKERD SERVICE MESH READY${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}What was installed:${NC}"
echo "  • Linkerd CRDs + CNI plugin + control plane (cniEnabled=true)"
if [ "${SKIP_VIZ}" = false ]; then
    echo "  • Linkerd Viz (dashboard, tap, metrics-api)"
fi
echo "  • MeshTLSAuthentication + Server CRs + strict AuthorizationPolicy"
echo "  • ServiceProfiles for retries (502/503/504) and 30s timeouts"
echo "  • Namespace injection enabled on ${APP_NAMESPACE}"
if [ "${SKIP_RESTART}" = false ]; then
    echo "  • Ecommerce workloads restarted for proxy injection"
fi
echo ""
echo -e "${YELLOW}Access:${NC}"
if [ "${SKIP_VIZ}" = false ]; then
    echo "  Linkerd Viz dashboard (service map, golden metrics, tap):"
    echo "    http://localhost:${VIZ_PORT}"
    echo "    kubectl -n ${LINKERD_VIZ_NAMESPACE} port-forward svc/web ${VIZ_PORT}:${VIZ_PORT}"
    echo ""
fi
echo "  Grafana Linkerd Golden Metrics dashboard:"
echo "    http://localhost:3030  (folder: E-Commerce → Linkerd Golden Metrics)"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
if command -v linkerd >/dev/null 2>&1; then
    echo "  linkerd check"
    echo "  linkerd viz stat deploy -n ${APP_NAMESPACE}"
    echo "  linkerd viz tap deploy/product-service -n ${APP_NAMESPACE}"
else
    echo "  (optional) brew install linkerd"
    echo "  linkerd check / linkerd viz stat deploy -n ${APP_NAMESPACE}"
fi
echo ""
echo -e "${YELLOW}NetworkPolicies:${NC}"
echo "  This script does NOT apply NetworkPolicies. Use:"
echo "    ${SCRIPT_DIR}/network-policies/deploy-np.sh --apply"
echo "    ${SCRIPT_DIR}/deploy.sh --policies-only"
echo ""
echo -e "${YELLOW}Kind caveats:${NC}"
echo "  • Cilium CNI recommended for NetworkPolicy enforcement alongside mesh"
echo "  • CNPG/RabbitMQ/Redis skip-injection/skip-ports configured in mesh/"
echo "  • Delete mesh: helm uninstall linkerd-viz -n ${LINKERD_VIZ_NAMESPACE}; helm uninstall linkerd-control-plane linkerd-cni linkerd-crds -n ${LINKERD_NAMESPACE}"
echo ""

if [ "${SKIP_VIZ}" = false ]; then
    print_step "13" "Linkerd Viz Port-Forward"
    maybe_start_viz_port_forward
fi

print_success "Done!"

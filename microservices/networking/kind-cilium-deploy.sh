#!/usr/bin/env bash
# Kind cluster with Cilium, then the ecommerce Helm chart.
#
# Cilium replaces kindnet so NetworkPolicy is enforced. kube-proxy stays in
# place so Kind NodePorts keep working. Policies under network-policies/ are
# not applied; run network-policies/apply.sh when you want them.
#
# Usage:
#   ./kind-cilium-deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "${SCRIPT_DIR}/../app" && pwd)"
CHART_PATH="${SCRIPT_DIR}/helm-ms-cnpg-vault-eso/ecommerce"
KIND_CONFIG="${SCRIPT_DIR}/kind-config-cilium.yaml"
POLICY_DIR="${SCRIPT_DIR}/network-policies"

CLUSTER_NAME="ecommerce-cilium"
NAMESPACE="ecommerce"
RELEASE_NAME="ecommerce-vault"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.0}"
CNPG_VERSION="1.22.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VAULT_PF_PID=""
cleanup() {
    if [[ -n "${VAULT_PF_PID}" ]]; then
        kill "${VAULT_PF_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
    exit 1
}

# ============================================================
# STEP 0: Prerequisites
# ============================================================
print_step "0" "Checking Prerequisites"

command -v docker >/dev/null 2>&1 || print_error "Docker is not installed"
print_success "Docker found"

command -v kind >/dev/null 2>&1 || print_error "Kind is not installed"
print_success "Kind found"

command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"
print_success "kubectl found"

command -v helm >/dev/null 2>&1 || print_error "Helm is not installed"
print_success "Helm found"

docker info >/dev/null 2>&1 || print_error "Docker is not running"
print_success "Docker is running"

[[ -f "${KIND_CONFIG}" ]] || print_error "Missing ${KIND_CONFIG}"
[[ -d "${CHART_PATH}" ]] || print_error "Missing Helm chart at ${CHART_PATH}"

# ============================================================
# STEP 1: Kind cluster without kindnet
# ============================================================
print_step "1" "Creating Kind Cluster"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    print_info "Cluster '${CLUSTER_NAME}' already exists"
    kubectl config use-context "kind-${CLUSTER_NAME}"
else
    print_info "Creating '${CLUSTER_NAME}' with Cilium as the CNI..."
    kind create cluster --config "${KIND_CONFIG}" --name "${CLUSTER_NAME}"
    print_success "Kind cluster created"
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# ============================================================
# STEP 2: Cilium
# ============================================================
print_step "2" "Installing Cilium ${CILIUM_VERSION}"

helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium

print_info "Nodes stay NotReady until Cilium writes the CNI config."
helm upgrade --install cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --namespace kube-system \
    --set operator.replicas=1 \
    --set kubeProxyReplacement=false \
    --set ipam.mode=kubernetes \
    --set routingMode=tunnel \
    --set image.pullPolicy=IfNotPresent \
    --wait \
    --timeout 6m

kubectl -n kube-system rollout status daemonset/cilium --timeout=180s
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=180s
kubectl wait --for=condition=Ready node --all --timeout=180s
print_success "Cilium is running and the node is Ready"

# ============================================================
# STEP 3: CloudNativePG
# ============================================================
print_step "3" "Installing CloudNativePG Operator"

if kubectl get deployment cnpg-controller-manager -n cnpg-system >/dev/null 2>&1; then
    print_info "CNPG operator is already installed"
else
    kubectl apply --server-side -f \
        "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-${CNPG_VERSION}.yaml"
    kubectl wait --for=condition=Available deployment/cnpg-controller-manager \
        -n cnpg-system --timeout=180s
    print_success "CNPG operator installed"
fi

# ============================================================
# STEP 4: Vault
# ============================================================
print_step "4" "Installing Vault"

helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

if helm status vault -n vault >/dev/null 2>&1; then
    print_info "Vault is already installed"
else
    helm install vault hashicorp/vault \
        -n vault \
        -f "${CHART_PATH}/vault/vault-values.yaml" \
        --wait \
        --timeout 5m
    print_success "Vault installed"
fi

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=180s
print_success "Vault is ready"

# ============================================================
# STEP 5: External Secrets Operator
# ============================================================
print_step "5" "Installing External Secrets Operator"

helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

if helm status external-secrets -n external-secrets >/dev/null 2>&1; then
    print_info "External Secrets Operator is already installed"
else
    helm install external-secrets external-secrets/external-secrets \
        -n external-secrets \
        --set installCRDs=true \
        --wait \
        --timeout 5m
    print_success "External Secrets Operator installed"
fi

kubectl wait --for=condition=Available deployment/external-secrets \
    -n external-secrets --timeout=180s

# ============================================================
# STEP 6: Vault secrets and ESO sync
# ============================================================
print_step "6" "Loading Secrets into Vault"

kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv >/dev/null 2>&1 \
    || print_info "KV engine already enabled"

kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/database \
    username="ecommerce_user" \
    password="secure_db_password_123"
kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/redis \
    password="redis_secure_password_456"
kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/rabbitmq \
    username="rabbitmq" \
    password="rabbitmq_secure_password_789"
kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/app \
    jwt_secret="your-super-secret-jwt-key-change-this-in-production-min-32-chars"
kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/razorpay \
    key_id="rzp_test_placeholder" \
    key_secret="placeholder_secret_key" \
    webhook_secret="whsec_placeholder"
print_success "Vault secrets written"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${CHART_PATH}/vault/cluster-secret-store.yaml"
kubectl apply -f "${CHART_PATH}/vault/external-secrets.yaml"

print_info "Waiting for External Secrets to sync..."
for secret in db-credentials redis-credentials rabbitmq-credentials app-secrets; do
    synced=0
    for _ in 1 2 3 4 5 6; do
        if kubectl get secret "${secret}" -n "${NAMESPACE}" >/dev/null 2>&1; then
            print_success "Secret '${secret}' synced"
            synced=1
            break
        fi
        sleep 5
    done
    [[ "${synced}" -eq 1 ]] || print_error "Secret '${secret}' was not synced from Vault"
done

# ============================================================
# STEP 7: Images
# ============================================================
print_step "7" "Building and Loading Images"

images=(
    "product-service:local|${APP_DIR}/services/product-service"
    "user-service:local|${APP_DIR}/services/user-service"
    "cart-service:local|${APP_DIR}/services/cart-service"
    "order-service:local|${APP_DIR}/services/order-service"
    "payment-service:local|${APP_DIR}/services/payment-service"
    "notification-service:local|${APP_DIR}/services/notification-service"
    "frontend:local|${APP_DIR}/frontend"
    "ms-ecom-seed:latest|${APP_DIR}/seed-job"
)

for entry in "${images[@]}"; do
    tag="${entry%%|*}"
    context="${entry#*|}"
    print_info "Building ${tag}..."
    docker build -t "${tag}" "${context}"
    kind load docker-image "${tag}" --name "${CLUSTER_NAME}"
    print_success "${tag} loaded into Kind"
done

# ============================================================
# STEP 8: Helm release
# ============================================================
print_step "8" "Deploying the Helm Chart"

helm lint "${CHART_PATH}"
print_success "Chart is valid"

if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    print_info "Upgrading ${RELEASE_NAME}..."
    helm upgrade "${RELEASE_NAME}" "${CHART_PATH}" \
        --namespace "${NAMESPACE}" \
        --timeout 10m
    print_success "Helm release upgraded"
else
    print_info "Installing ${RELEASE_NAME}..."
    helm install "${RELEASE_NAME}" "${CHART_PATH}" \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        --timeout 10m
    print_success "Helm release installed"
fi

# ============================================================
# STEP 9: Wait for workloads
# ============================================================
print_step "9" "Waiting for Workloads"

print_info "CNPG clusters can take a few minutes..."
for cluster in products users orders payments; do
    elapsed=0
    until [[ "$(kubectl get cluster "${cluster}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Cluster in healthy state" ]]; do
        if [[ "${elapsed}" -ge 300 ]]; then
            print_error "Timed out waiting for CNPG cluster ${cluster}"
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo -n "."
    done
    echo ""
    print_success "${cluster} cluster is healthy"
done

kubectl rollout status deployment/redis -n "${NAMESPACE}" --timeout=180s
kubectl rollout status statefulset/rabbitmq -n "${NAMESPACE}" --timeout=180s
kubectl rollout status deployment/mailpit -n "${NAMESPACE}" --timeout=180s

for service in product-service user-service cart-service order-service payment-service notification-service api-gateway frontend; do
    kubectl rollout status "deployment/${service}" -n "${NAMESPACE}" --timeout=180s
    print_success "${service} is available"
done

# ============================================================
# STEP 10: Seed data
# ============================================================
print_step "10" "Seeding Data"

kubectl exec -n "${NAMESPACE}" products-1 -- \
    psql -U postgres -d products -c "TRUNCATE TABLE products RESTART IDENTITY CASCADE;" \
    >/dev/null 2>&1 && print_success "Products table truncated" \
    || print_info "Products truncate skipped"

kubectl delete job seed-data-manual seed-data-job -n "${NAMESPACE}" --ignore-not-found
kubectl apply -f "${APP_DIR}/seed-job/seed-job.yaml"

if kubectl wait --for=condition=complete job/seed-data-manual -n "${NAMESPACE}" --timeout=180s; then
    print_success "Seed job completed"
    kubectl logs job/seed-data-manual -n "${NAMESPACE}" || true
else
    print_info "Seed job did not finish. Logs:"
    kubectl logs job/seed-data-manual -n "${NAMESPACE}" || true
fi

# ============================================================
# STEP 11: Done — policies stay unapplied
# ============================================================
print_step "11" "Cluster is Up"

echo -e "${YELLOW}Access:${NC}"
echo "  Frontend:     http://localhost:4000"
echo "  API Gateway:  http://localhost:9080"
echo "  Vault UI:     http://localhost:8200   (token: root)"
echo "  Mailpit:      http://localhost:8025"
echo "  RabbitMQ UI:  kubectl port-forward -n ${NAMESPACE} svc/rabbitmq 15672:15672"
echo ""
echo -e "${YELLOW}Cilium:${NC}"
echo "  kubectl -n kube-system get pods -l k8s-app=cilium"
echo "  kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status"
echo ""
echo -e "${YELLOW}Network policies are written and not applied:${NC}"
echo "  ${POLICY_DIR}"
echo ""
echo "  Apply the full set when you want default-deny plus the allows:"
echo "    ${POLICY_DIR}/apply.sh"
echo ""
echo "  Or apply one file:"
echo "    ${POLICY_DIR}/apply.sh 40-api-gateway.yaml"
echo ""
echo "  What the set allows:"
echo "    outside  -> frontend:80, api-gateway:80, mailpit:8025"
echo "    gateway  -> product, user, cart, order, payment, notification"
echo "    cart     -> product-service, redis"
echo "    order    -> product-service, cart-service, orders DB, rabbitmq"
echo "    payment  -> order-service, payments DB"
echo "    notify   -> rabbitmq, mailpit SMTP"
echo "    product/user -> their own database"
echo "    cnpg-system -> database pods (5432 and 8000)"
echo ""
echo "  Check from cart-service after applying (allowed, then denied):"
echo "    kubectl -n ${NAMESPACE} exec deploy/cart-service -- node -e \"fetch('http://product-service:8001/health',{signal:AbortSignal.timeout(3000)}).then(r=>r.text()).then(console.log)\""
echo "    kubectl -n ${NAMESPACE} exec deploy/cart-service -- node -e \"fetch('http://user-service:8002/health',{signal:AbortSignal.timeout(3000)}).then(r=>r.text()).then(console.log)\""
echo ""
echo "  Remove the policies without deleting the app:"
echo "    kubectl delete -f ${POLICY_DIR}"
echo ""
echo -e "${YELLOW}Cleanup:${NC}"
echo "  helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo "  helm uninstall vault -n vault"
echo "  helm uninstall external-secrets -n external-secrets"
echo "  kind delete cluster --name ${CLUSTER_NAME}"
echo ""

if curl -sf --connect-timeout 3 http://localhost:9080/health | grep -q "OK"; then
    print_success "API Gateway is healthy"
else
    print_info "API Gateway is not answering yet. Try: curl http://localhost:9080/health"
fi

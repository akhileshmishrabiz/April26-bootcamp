#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-vault-eso-demo}"
VAULT_NAMESPACE="vault"
ESO_NAMESPACE="external-secrets"
DEMO_NAMESPACE="demo"
VAULT_ROOT_TOKEN="root"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

for command in docker kind kubectl helm; do
  if ! command_exists "$command"; then
    echo "ERROR: '$command' is required but is not installed."
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running."
  exit 1
fi

echo "==> Creating kind cluster: ${CLUSTER_NAME}"
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}"
else
  echo "Cluster already exists; reusing it."
fi
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

echo "==> Adding Helm repositories"
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo update

echo "==> Installing Vault in development mode"
helm upgrade --install vault hashicorp/vault \
  --namespace "${VAULT_NAMESPACE}" \
  --create-namespace \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken="${VAULT_ROOT_TOKEN}" \
  --set injector.enabled=false \
  --wait
kubectl -n "${VAULT_NAMESPACE}" wait \
  --for=condition=Ready pod/vault-0 --timeout=180s

echo "==> Installing External Secrets Operator"
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace "${ESO_NAMESPACE}" \
  --create-namespace \
  --set installCRDs=true \
  --wait
kubectl -n "${ESO_NAMESPACE}" wait \
  --for=condition=Available deployment --all --timeout=180s

echo "==> Creating demo namespace"
kubectl create namespace "${DEMO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Allowing Vault to validate Kubernetes service-account tokens"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-token-reviewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault
    namespace: ${VAULT_NAMESPACE}
EOF

vault_exec() {
  kubectl -n "${VAULT_NAMESPACE}" exec vault-0 -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${VAULT_ROOT_TOKEN}" vault "$@"
}

echo "==> Enabling Vault KV v2 secrets engine"
vault_exec secrets enable -path=secret kv-v2 2>/dev/null || true

echo "==> Enabling and configuring Vault Kubernetes authentication"
vault_exec auth enable kubernetes 2>/dev/null || true
vault_exec write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

echo "==> Creating least-privilege Vault policy and Kubernetes auth role"
kubectl -n "${VAULT_NAMESPACE}" exec -i vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${VAULT_ROOT_TOKEN}" \
  vault policy write eso-demo - <<'EOF'
path "secret/data/demo" {
  capabilities = ["read"]
}
EOF

vault_exec write auth/kubernetes/role/eso-demo \
  bound_service_account_names=eso-vault-auth \
  bound_service_account_namespaces="${DEMO_NAMESPACE}" \
  policies=eso-demo \
  audience=vault \
  ttl=1h

echo "==> Saving demo credentials with the separate Vault command script"
if VAULT_NAMESPACE="${VAULT_NAMESPACE}" VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN}" \
  "${SCRIPT_DIR}/vault-secrets.sh" get >/dev/null 2>&1; then
  VAULT_NAMESPACE="${VAULT_NAMESPACE}" VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN}" \
    "${SCRIPT_DIR}/vault-secrets.sh" update demo-user super-secret-password
else
  VAULT_NAMESPACE="${VAULT_NAMESPACE}" VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN}" \
    "${SCRIPT_DIR}/vault-secrets.sh" create demo-user super-secret-password
fi

echo "==> Applying the standalone ESO configuration"
kubectl apply -f "${SCRIPT_DIR}/eso-config.yaml"

echo "==> Waiting for ESO to create the Kubernetes Secret"
for _ in {1..30}; do
  if kubectl -n "${DEMO_NAMESPACE}" get secret demo-credentials >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! kubectl -n "${DEMO_NAMESPACE}" get secret demo-credentials >/dev/null 2>&1; then
  echo "ERROR: Secret was not created. Run:"
  echo "  kubectl -n ${DEMO_NAMESPACE} describe externalsecret demo-credentials"
  exit 1
fi

echo
echo "Demo is ready."
echo "Username: $(kubectl -n "${DEMO_NAMESPACE}" get secret demo-credentials -o jsonpath='{.data.username}' | base64 --decode)"
echo "Password: $(kubectl -n "${DEMO_NAMESPACE}" get secret demo-credentials -o jsonpath='{.data.password}' | base64 --decode)"
echo
echo "Delete everything with:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"

#!/usr/bin/env bash
set -euo pipefail

# Create a fresh kind cluster, label/taint nodes, and deploy all scheduling demos.
#
# Prerequisites: docker, kind, kubectl
#
# Run from this directory:
#   bash deploy.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-pod-scheduling}"

for command_name in docker kind kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: ${command_name} is required but is not installed." >&2
    exit 1
  fi
done

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Deleting existing kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
fi

echo "Creating kind cluster '${CLUSTER_NAME}' (1 control-plane + 3 workers)..."
kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config.yaml"

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

bash "${SCRIPT_DIR}/setup-nodes.sh"

echo "Deploying scheduling demos..."
kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/"

echo "Waiting for deployments to roll out..."
kubectl rollout status deployment/toleration-demo -n scheduling-demo --timeout=120s
kubectl rollout status deployment/affinity-demo -n scheduling-demo --timeout=120s
kubectl rollout status deployment/anti-affinity-demo -n scheduling-demo --timeout=120s
kubectl rollout status deployment/spread-demo -n scheduling-demo --timeout=120s

echo
echo "Cluster '${CLUSTER_NAME}' is ready. Open demo.md for the walkthrough."
echo
kubectl get pods -n scheduling-demo -o wide

#!/usr/bin/env bash
set -euo pipefail

# Creates a fresh kind cluster and deploys both StatefulSet demos.
#
# Prerequisites: docker, kind, kubectl, curl
#
# Run:
#   bash deploy.sh
#
# Full walkthrough: see EXERCISE.md

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-statefulsets-demo}"

for command_name in docker kind kubectl curl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: ${command_name} is required but is not installed." >&2
    exit 1
  fi
done

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "Deleting existing kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}"
fi

echo "Creating fresh kind cluster '${CLUSTER_NAME}'..."
kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config.yaml"

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

bash "${SCRIPT_DIR}/demo1-postgres-statefulset/deploy.sh"
bash "${SCRIPT_DIR}/demo2-cnpg-postgres/deploy.sh"

echo
echo "All demos deployed on cluster '${CLUSTER_NAME}'."
echo "Open EXERCISE.md for step-by-step validation."

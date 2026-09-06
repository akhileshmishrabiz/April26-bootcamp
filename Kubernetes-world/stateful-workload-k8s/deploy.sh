#!/usr/bin/env bash
set -euo pipefail

# Start fresh: delete existing cluster, create a new kind cluster with host volume,
# then deploy both demos.
#
# Prerequisites: docker, kind, kubectl
#
# Run from this directory:
#   bash deploy.sh
#
# Full walkthrough: see EXERCISE.md
#
# Demo 1 (pod persistence):
#   bash demo1-pod-persistence/deploy.sh
#
# Demo 2 (shared volume across pods):
#   bash demo2-shared-volume/deploy.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-stateful-vol}"

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

echo "Creating fresh kind cluster '${CLUSTER_NAME}'..."
kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config-vol.yaml"

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

bash "${SCRIPT_DIR}/demo1-pod-persistence/deploy.sh"
bash "${SCRIPT_DIR}/demo2-shared-volume/deploy.sh"

echo
echo "All demos deployed on cluster '${CLUSTER_NAME}'."
echo "See demo1-pod-persistence/deploy.sh and demo2-shared-volume/deploy.sh for walkthrough commands."

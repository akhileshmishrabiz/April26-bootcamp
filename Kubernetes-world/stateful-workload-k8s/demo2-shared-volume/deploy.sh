#!/usr/bin/env bash
set -euo pipefail

# Demo 2: Multiple pods writing to the same volume
#
# Three pods share one ReadWriteMany PVC. Each appends to /data/shared.log with
# its pod name, so you can see lines from every pod in one file.
#
# Deploy (cluster must already exist):
#   bash deploy.sh
#
# Step 1 — list pods:
#   kubectl -n demo2-shared get pods -l app=shared-writer -o wide
#
# Step 2 — watch the shared log (all pods writing to one file):
#   kubectl -n demo2-shared exec deploy/shared-writer -- tail -f /data/shared.log
#
# Step 3 — see per-pod files on the same disk:
#   POD=$(kubectl -n demo2-shared get pod -l app=shared-writer -o jsonpath='{.items[0].metadata.name}')
#   kubectl -n demo2-shared exec "$POD" -- ls -la /data/pods/
#
# Host copy (optional):
#   tail -f ../host-volume-data/demo2/shared.log

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"
HOST_DATA_DIR="${SCRIPT_DIR}/../host-volume-data/demo2"

mkdir -p "${HOST_DATA_DIR}"

kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/storage.yaml"
kubectl apply -f "${K8S_DIR}/deployment.yaml"

kubectl -n demo2-shared rollout status deployment/shared-writer --timeout=120s

echo
echo "Demo 2 ready (namespace: demo2-shared)"
echo "Watch shared log: kubectl -n demo2-shared exec deploy/shared-writer -- tail -f /data/shared.log"
echo "List pods:        kubectl -n demo2-shared get pods -l app=shared-writer"
echo "Host file:          ${HOST_DATA_DIR}/shared.log"

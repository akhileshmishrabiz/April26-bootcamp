#!/usr/bin/env bash
set -euo pipefail

# Demo 1: Pod persistence across pod lifecycle
#
# One Deployment pod writes timestamps to a PVC-backed file. When the pod is
# deleted and recreated, the new pod mounts the same volume and continues
# appending — old lines remain visible.
#
# Deploy (cluster must already exist):
#   bash deploy.sh
#
# Step 1 — watch the pod write data:
#   kubectl -n demo1-persistence get pods -l app=data-writer
#   kubectl -n demo1-persistence exec deploy/data-writer -- tail -f /data/events.log
#
# Step 2 — kill the pod (Deployment creates a new one):
#   kubectl -n demo1-persistence delete pod -l app=data-writer
#   kubectl -n demo1-persistence wait --for=condition=Ready pod -l app=data-writer --timeout=60s
#
# Step 3 — new pod still sees old data plus new lines:
#   kubectl -n demo1-persistence exec deploy/data-writer -- cat /data/events.log
#
# Host copy (optional):
#   cat ../host-volume-data/demo1/events.log

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"
HOST_DATA_DIR="${SCRIPT_DIR}/../host-volume-data/demo1"

mkdir -p "${HOST_DATA_DIR}"

kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/storage.yaml"
kubectl apply -f "${K8S_DIR}/deployment.yaml"

kubectl -n demo1-persistence rollout status deployment/data-writer --timeout=120s

echo
echo "Demo 1 ready (namespace: demo1-persistence)"
echo "Watch log:  kubectl -n demo1-persistence exec deploy/data-writer -- tail -f /data/events.log"
echo "Kill pod:   kubectl -n demo1-persistence delete pod -l app=data-writer"
echo "Host file:  ${HOST_DATA_DIR}/events.log"

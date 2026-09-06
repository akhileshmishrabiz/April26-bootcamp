#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-pod-scheduling}"

echo "Waiting for nodes to become Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

WORKER="${CLUSTER_NAME}-worker"
WORKER2="${CLUSTER_NAME}-worker2"
WORKER3="${CLUSTER_NAME}-worker3"

echo "Labeling nodes for affinity and spread demos..."
kubectl label node "${WORKER}" node-role=frontend demo-zone=zone-a --overwrite
kubectl label node "${WORKER2}" node-role=backend demo-zone=zone-b --overwrite
kubectl label node "${WORKER3}" node-role=special demo-zone=zone-c --overwrite

echo "Tainting ${WORKER3} (only pods with a matching toleration can schedule here)..."
kubectl taint node "${WORKER3}" special=true:NoSchedule --overwrite

echo "Node setup complete:"
kubectl get nodes -L node-role,demo-zone --show-labels | grep -E 'NAME|worker'

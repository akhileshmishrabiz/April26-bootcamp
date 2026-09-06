#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/secret.yaml"
kubectl apply -f "${K8S_DIR}/service.yaml"
kubectl apply -f "${K8S_DIR}/statefulset.yaml"

echo "Waiting for postgres-0..."
kubectl -n demo1-statefulset wait --for=condition=Ready pod/postgres-0 --timeout=180s

echo "Waiting for postgres-1..."
kubectl -n demo1-statefulset wait --for=condition=Ready pod/postgres-1 --timeout=180s

echo "Waiting for postgres-2..."
kubectl -n demo1-statefulset wait --for=condition=Ready pod/postgres-2 --timeout=180s

echo
echo "Demo 1 ready (namespace: demo1-statefulset)"
echo "Pods:     kubectl -n demo1-statefulset get pods -l app=postgres"
echo "DNS test: kubectl -n demo1-statefulset run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup postgres-0.postgres.demo1-statefulset.svc.cluster.local"
echo "SQL:      kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c \"SELECT version();\""

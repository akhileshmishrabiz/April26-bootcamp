#!/usr/bin/env bash
set -euo pipefail

CNPG_VERSION="${CNPG_VERSION:-1.30.0}"
CNPG_MANIFEST="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-${CNPG_VERSION}.yaml"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

if ! kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then
  echo "Installing CloudNativePG operator ${CNPG_VERSION}..."
  kubectl apply --server-side -f "${CNPG_MANIFEST}"
  kubectl rollout status deployment -n cnpg-system cnpg-controller-manager --timeout=180s
else
  echo "CloudNativePG operator already installed."
fi

kubectl apply -f "${K8S_DIR}/namespace.yaml"

echo "Starting MinIO for backups..."
kubectl apply -f "${K8S_DIR}/backup.yaml"
kubectl -n demo2-cnpg rollout status deployment/minio --timeout=180s
kubectl -n demo2-cnpg delete job minio-init-bucket --ignore-not-found
kubectl apply -f "${K8S_DIR}/backup-init-job.yaml"
kubectl -n demo2-cnpg wait --for=condition=complete job/minio-init-bucket --timeout=180s

kubectl apply -f "${K8S_DIR}/cluster.yaml"

echo "Waiting for CNPG cluster to become ready (this can take a few minutes)..."
kubectl -n demo2-cnpg wait --for=condition=Ready cluster/demo-pg --timeout=600s

echo "Enabling scheduled backups..."
kubectl apply -f "${K8S_DIR}/backup-schedule.yaml"

echo "Enabling connection pooling..."
kubectl apply -f "${K8S_DIR}/pooler.yaml"
kubectl -n demo2-cnpg wait --for=condition=Ready pod -l cnpg.io/poolerName=demo-pg-pooler-rw --timeout=180s

echo
echo "Demo 2 ready (namespace: demo2-cnpg)"
echo "Cluster:  kubectl -n demo2-cnpg get cluster demo-pg"
echo "Pods:     kubectl -n demo2-cnpg get pods"
echo "Services: kubectl -n demo2-cnpg get svc"
echo "Primary:  kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='Primary={.status.currentPrimary}{\"\\n\"}'"
echo "Backups:  kubectl -n demo2-cnpg get backup,scheduledbackup"
echo "Pooler:   kubectl -n demo2-cnpg get pooler,svc demo-pg-pooler-rw"
echo "SQL (rw): kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password psql -U appuser -d appdb -h 127.0.0.1 -c \"SELECT version();\""
echo "SQL (pool): kubectl -n demo2-cnpg run psql-pool --rm -it --restart=Never --image=postgres:16 --env PGPASSWORD=demo-password -- psql -h demo-pg-pooler-rw -U appuser -d appdb -c 'SELECT 1;'"

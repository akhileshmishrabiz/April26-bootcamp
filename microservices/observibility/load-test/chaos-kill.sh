#!/bin/bash
#
# Forcefully kill pods during load tests to observe resilience.
#
# Usage:
#   ./chaos-kill.sh --target product-service
#   ./chaos-kill.sh --target order-service --repeat 3 --interval 30
#   ./chaos-kill.sh --random [--interval 45]
#   ./chaos-kill.sh --all-once
#   ./chaos-kill.sh --target products --include-db   # CNPG postgres cluster (dangerous)
#
# Safety:
#   - Requires kubectl context kind-ecommerce-vault
#   - Never kills CNPG postgres pods unless --include-db is set
#
# Targets (app label):
#   product-service, user-service, cart-service, order-service,
#   payment-service, api-gateway, redis, rabbitmq
#
# CNPG clusters (--include-db only):
#   products, users, orders, payments
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-ecommerce}"
REQUIRED_CONTEXT="${REQUIRED_CONTEXT:-kind-ecommerce-vault}"

TARGET=""
MODE=""
REPEAT=1
INTERVAL=30
INCLUDE_DB=false

MICROSERVICES=(
  product-service
  user-service
  cart-service
  order-service
  payment-service
  api-gateway
  redis
  rabbitmq
)

CNPG_CLUSTERS=(products users orders payments)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${YELLOW}[chaos-kill]${NC} $*"; }
ok()   { echo -e "${GREEN}[chaos-kill]${NC} $*"; }
err()  { echo -e "${RED}[chaos-kill]${NC} $*" >&2; }

usage() {
  head -n 22 "$0" | tail -n +2 | sed 's/^# \?//'
  exit 0
}

is_microservice_target() {
  local name=$1
  local svc
  for svc in "${MICROSERVICES[@]}"; do
    [[ "$svc" == "$name" ]] && return 0
  done
  return 1
}

is_cnpg_target() {
  local name=$1
  local cluster
  for cluster in "${CNPG_CLUSTERS[@]}"; do
    [[ "$cluster" == "$name" ]] && return 0
  done
  return 1
}

check_context() {
  if ! command -v kubectl >/dev/null 2>&1; then
    err "kubectl is not installed."
    exit 1
  fi

  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$ctx" != "$REQUIRED_CONTEXT" ]]; then
    err "Refusing to run: kubectl context is '${ctx:-<none>}', expected '${REQUIRED_CONTEXT}'"
    err "Switch with: kubectl config use-context ${REQUIRED_CONTEXT}"
    exit 1
  fi
  ok "Cluster context verified: ${ctx}"
}

kill_app_target() {
  local target=$1
  log "Force-killing pod(s) with app=${target} in namespace ${NAMESPACE} ..."

  local pods
  pods="$(kubectl get pods -n "${NAMESPACE}" -l "app=${target}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$pods" ]]; then
    err "No pods found for app=${target} in namespace ${NAMESPACE}"
    return 1
  fi

  kubectl delete pod -l "app=${target}" -n "${NAMESPACE}" --force --grace-period=0
  ok "Killed app=${target} — Kubernetes will recreate the pod(s)"
}

kill_cnpg_target() {
  local cluster=$1
  log "Force-killing CNPG pod(s) for cluster=${cluster} in namespace ${NAMESPACE} ..."

  local pods
  pods="$(kubectl get pods -n "${NAMESPACE}" -l "cnpg.io/cluster=${cluster}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$pods" ]]; then
    err "No CNPG pods found for cluster=${cluster} in namespace ${NAMESPACE}"
    return 1
  fi

  kubectl delete pod -l "cnpg.io/cluster=${cluster}" -n "${NAMESPACE}" --force --grace-period=0
  ok "Killed CNPG cluster=${cluster} — operator will recreate pod(s)"
}

kill_target() {
  local target=$1

  if is_cnpg_target "$target"; then
    if [[ "$INCLUDE_DB" != true ]]; then
      err "Refusing to kill CNPG postgres cluster '${target}' without --include-db"
      return 1
    fi
    kill_cnpg_target "$target"
    return $?
  fi

  if ! is_microservice_target "$target"; then
    err "Unknown target '${target}'"
    err "Valid microservices: ${MICROSERVICES[*]}"
    err "Valid CNPG clusters (--include-db): ${CNPG_CLUSTERS[*]}"
    return 1
  fi

  kill_app_target "$target"
}

pick_random_target() {
  echo "${MICROSERVICES[$RANDOM % ${#MICROSERVICES[@]}]}"
}

run_random_loop() {
  log "Random chaos mode: killing a random microservice every ${INTERVAL}s (Ctrl+C to stop)"
  while true; do
    local target
    target="$(pick_random_target)"
    kill_app_target "$target" || true
    sleep "${INTERVAL}"
  done
}

run_all_once() {
  log "Killing one pod from each microservice deployment sequentially ..."
  local target
  for target in "${MICROSERVICES[@]}"; do
    kill_app_target "$target" || true
    sleep 5
  done
  ok "All-once chaos complete"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      MODE="target"
      shift 2
      ;;
    --repeat)
      REPEAT="${2:-1}"
      shift 2
      ;;
    --interval)
      INTERVAL="${2:-30}"
      shift 2
      ;;
    --random)
      MODE="random"
      shift
      ;;
    --all-once)
      MODE="all-once"
      shift
      ;;
    --include-db)
      INCLUDE_DB=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      err "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  err "No mode specified."
  usage
fi

check_context

case "$MODE" in
  target)
    if [[ -z "$TARGET" ]]; then
      err "--target requires a service name"
      exit 1
    fi
    for ((i = 1; i <= REPEAT; i++)); do
      log "Kill ${i}/${REPEAT}: ${TARGET}"
      kill_target "$TARGET" || true
      if [[ "$i" -lt "$REPEAT" ]]; then
        log "Waiting ${INTERVAL}s before next kill ..."
        sleep "${INTERVAL}"
      fi
    done
    ;;
  random)
    run_random_loop
    ;;
  all-once)
    run_all_once
    ;;
esac

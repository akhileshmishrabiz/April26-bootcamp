#!/bin/bash
#
# One-command "maximum pain" test: high RPS load + random pod chaos.
#
# Usage:
#   ./run-peak-chaos.sh                  # rps100 + chaos, then rps200 + chaos
#   ./run-peak-chaos.sh --rps-only       # rps100 only (skip rps200)
#
# What it does:
#   1. Starts chaos-kill.sh --random (kills a random service every 45s)
#   2. Runs rps100 → rps200 profiles back-to-back with CHAOS=1
#   3. Cleans up chaos on exit (including Ctrl+C)
#
# Watch during the run:
#   Grafana Golden Metrics + Latency & Errors dashboards at http://localhost:3030
#   Per-service RPS tags: product-service, user-service, cart-service,
#                         order-service, payment-service
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAOS_INTERVAL="${CHAOS_INTERVAL:-45}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"
CHAOS_PID=""
RPS_ONLY=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${YELLOW}[peak-chaos]${NC} $*"; }
ok()   { echo -e "${GREEN}[peak-chaos]${NC} $*"; }
err()  { echo -e "${RED}[peak-chaos]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[peak-chaos] WARNING:${NC} $*"; }

cleanup() {
  if [[ -n "${CHAOS_PID}" ]] && kill -0 "${CHAOS_PID}" 2>/dev/null; then
    log "Stopping chaos process (pid ${CHAOS_PID}) ..."
    kill "${CHAOS_PID}" 2>/dev/null || true
    wait "${CHAOS_PID}" 2>/dev/null || true
    CHAOS_PID=""
  fi
}

trap cleanup EXIT INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rps-only) RPS_ONLY=true; shift ;;
    --help|-h)  head -n 18 "$0" | tail -n +2 | sed 's/^# \?//'; exit 0 ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

export CHAOS=1

warn "RPS-driven chaos test — targets ~500+ RPS (rps100) then ~1000+ RPS (rps200)."
warn "Random pod kills + high arrival rate will cause latency spikes, errors, and possible OOM."
warn "Ensure observibility stack is deployed and Grafana is open before starting."
echo ""

log "Checking API gateway ..."
if ! curl -sf --connect-timeout 5 "http://localhost:9080/health" >/dev/null; then
  err "API gateway not reachable at http://localhost:9080"
  err "Start the stack first: cd observibility && ./deploy.sh"
  exit 1
fi
ok "API gateway is healthy"
echo ""

log "Starting random chaos (kill random service every ${CHAOS_INTERVAL}s) ..."
"${SCRIPT_DIR}/chaos-kill.sh" --random --interval "${CHAOS_INTERVAL}" &
CHAOS_PID=$!
ok "Chaos running in background (pid ${CHAOS_PID})"
echo ""

if [[ "$RPS_ONLY" == true ]]; then
  PROFILES=(rps100)
else
  PROFILES=(rps100 rps200)
fi

FAILED=()
PASSED=()

for i in "${!PROFILES[@]}"; do
  profile="${PROFILES[$i]}"
  log "=========================================="
  log "Profile ${i+1}/${#PROFILES[@]}: ${profile}"
  log "=========================================="

  set +e
  "${SCRIPT_DIR}/run-load-test.sh" "--${profile}"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    PASSED+=("${profile}")
    ok "Profile '${profile}' completed"
  else
    FAILED+=("${profile}")
    err "Profile '${profile}' exited with code ${rc} (may be expected under chaos)"
  fi

  if [[ $i -lt $((${#PROFILES[@]} - 1)) ]]; then
    log "Cooling down for ${COOLDOWN_SECONDS}s ..."
    sleep "${COOLDOWN_SECONDS}"
  fi
done

echo ""
log "=========================================="
log "RPS + chaos summary"
log "=========================================="
ok "Completed (${#PASSED[@]}): ${PASSED[*]:-none}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  err "Threshold failures (${#FAILED[@]}): ${FAILED[*]}"
fi

echo ""
log "Review impact in Grafana:"
log "  Golden Metrics dashboard:  http://localhost:3030  (success rate, RPS, latency)"
log "  Latency & Errors dashboard: http://localhost:3030  (p95/p99, 5xx rates)"
log "  Prometheus:                 http://localhost:9090"
echo ""
log "Look for: per-service RPS ~100/200, error rate spikes during pod kills,"
log "          recovery after pod recreation, elevated p99 under rps200."

if [[ ${#FAILED[@]} -gt 0 ]]; then
  exit 1
fi

#!/bin/bash
#
# Master orchestrator — runs k6 load profiles sequentially.
#
# Usage:
#   ./run-all-load-tests.sh                    # RPS progression: smoke → rps50 → rps100
#   ./run-all-load-tests.sh --with-chaos       # random pod kills during each test
#   ./run-all-load-tests.sh --extreme          # also run rps200 (very heavy)
#   ./run-all-load-tests.sh --include-soak     # also run rps100-soak (adds 15min+)
#   ./run-all-load-tests.sh --legacy           # old VU-based profile sequence
#   ./run-all-load-tests.sh --peak-only --with-chaos  # rps100 only with chaos
#
# Default order: smoke → rps50 → rps100
# With --extreme: smoke → rps50 → rps100 → rps200
# With --include-soak: ... → rps100-soak
#
# Environment:
#   COOLDOWN_SECONDS=30     Pause between profiles (default 30)
#   CHAOS_INTERVAL=30       Random kill interval when --with-chaos
#   CHAOS=1                 Passed to k6 for lenient thresholds
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"
CHAOS_INTERVAL="${CHAOS_INTERVAL:-30}"
WITH_CHAOS=false
PEAK_ONLY=false
INCLUDE_SOAK=false
EXTREME=false
LEGACY=false
CHAOS_PID=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${YELLOW}[run-all]${NC} $*"; }
ok()   { echo -e "${GREEN}[run-all]${NC} $*"; }
err()  { echo -e "${RED}[run-all]${NC} $*" >&2; }

usage() {
  head -n 22 "$0" | tail -n +2 | sed 's/^# \?//'
  exit 0
}

cleanup_chaos() {
  if [[ -n "${CHAOS_PID}" ]] && kill -0 "${CHAOS_PID}" 2>/dev/null; then
    log "Stopping background chaos process (pid ${CHAOS_PID}) ..."
    kill "${CHAOS_PID}" 2>/dev/null || true
    wait "${CHAOS_PID}" 2>/dev/null || true
    CHAOS_PID=""
  fi
}

start_chaos() {
  cleanup_chaos
  log "Starting random chaos (interval ${CHAOS_INTERVAL}s) ..."
  "${SCRIPT_DIR}/chaos-kill.sh" --random --interval "${CHAOS_INTERVAL}" &
  CHAOS_PID=$!
}

stop_chaos() {
  cleanup_chaos
}

trap cleanup_chaos EXIT INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-chaos)   WITH_CHAOS=true; shift ;;
    --peak-only)    PEAK_ONLY=true; shift ;;
    --include-soak) INCLUDE_SOAK=true; shift ;;
    --extreme)      EXTREME=true; shift ;;
    --legacy)       LEGACY=true; shift ;;
    --help|-h)      usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

if [[ "$PEAK_ONLY" == true ]]; then
  PROFILES=(rps100)
elif [[ "$LEGACY" == true ]]; then
  PROFILES=(smoke load stress spike peak breakpoint)
  if [[ "$INCLUDE_SOAK" == true ]]; then
    PROFILES=(smoke load stress spike peak soak breakpoint)
  fi
else
  PROFILES=(smoke rps50 rps100)
  if [[ "$EXTREME" == true ]]; then
    PROFILES+=(rps200)
  fi
  if [[ "$INCLUDE_SOAK" == true ]]; then
    PROFILES+=(rps100-soak)
  fi
fi

export CHAOS=1

log "Profiles to run: ${PROFILES[*]}"
log "Cooldown between profiles: ${COOLDOWN_SECONDS}s"
if [[ "$WITH_CHAOS" == true ]]; then
  log "Chaos enabled: random pod kills every ${CHAOS_INTERVAL}s"
fi
echo ""

FAILED=()
PASSED=()

run_profile() {
  local profile=$1
  local flag="--${profile}"

  log "=========================================="
  log "Starting profile: ${profile}"
  log "=========================================="

  if [[ "$WITH_CHAOS" == true ]]; then
    start_chaos
  fi

  set +e
  "${SCRIPT_DIR}/run-load-test.sh" "${flag}"
  local rc=$?
  set -e

  if [[ "$WITH_CHAOS" == true ]]; then
    stop_chaos
  fi

  if [[ $rc -eq 0 ]]; then
    PASSED+=("${profile}")
    ok "Profile '${profile}' completed"
  else
    FAILED+=("${profile}")
    err "Profile '${profile}' failed (exit ${rc})"
  fi
}

for i in "${!PROFILES[@]}"; do
  profile="${PROFILES[$i]}"
  run_profile "${profile}"

  if [[ $i -lt $((${#PROFILES[@]} - 1)) ]]; then
    log "Cooling down for ${COOLDOWN_SECONDS}s ..."
    sleep "${COOLDOWN_SECONDS}"
  fi
done

echo ""
log "=========================================="
log "Run-all summary"
log "=========================================="
ok "Passed (${#PASSED[@]}): ${PASSED[*]:-none}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  err "Failed (${#FAILED[@]}): ${FAILED[*]}"
  echo ""
  err "Some profiles exceeded thresholds — expected under rps200 + chaos on Kind."
  err "Review Grafana: http://localhost:3030"
  exit 1
fi

ok "All profiles completed successfully"
echo ""
log "Watch dashboards for post-run metrics:"
log "  Grafana Golden Metrics:  http://localhost:3030"
log "  Latency & Errors:        http://localhost:3030"
log "  Prometheus:              http://localhost:9090"

#!/bin/bash
#
# k6 load test runner for the e-commerce microservices stack.
#
# Usage:
#   ./run-load-test.sh                  # rps100 profile (default): 100 req/s per HTTP service
#   ./run-load-test.sh --rps100         # 100 req/s × 5 services + journey (~500+ RPS total)
#   ./run-load-test.sh --rps50          # 50 req/s per service × 5 min
#   ./run-load-test.sh --rps200         # 200 req/s per service × 3 min (extreme)
#   ./run-load-test.sh --rps100-soak    # 100 req/s per service × 15 min
#   ./run-load-test.sh --rps20          # 20 req/s per service × 30s (quick validation)
#
# Legacy VU-based profiles (still supported):
#   ./run-load-test.sh --smoke          # 5 VUs for 1 minute
#   ./run-load-test.sh --load           # ramp to 50 VUs, sustain 10min
#   ./run-load-test.sh --stress         # ramp to 200 VUs
#   ./run-load-test.sh --spike          # sudden spike to 300 VUs
#   ./run-load-test.sh --peak           # ramp to 500 VUs
#   ./run-load-test.sh --soak            # 30 VUs sustained
#   ./run-load-test.sh --breakpoint     # ramp 50→500 VUs
#
# Environment:
#   API_URL=http://localhost:9080       API gateway base URL
#   K6_PROFILE=rps100|rps50|...         Override profile without flags
#   RPS_PER_SERVICE=100                 Override per-service RPS (with custom TEST_DURATION)
#   TEST_DURATION=5m                    Override scenario duration
#   CHAOS=1                             Lenient thresholds for chaos testing
#   SOAK_DURATION=10m|30m               Legacy soak sustain duration
#   EMAIL=john.doe@example.com          Login email (seed user)
#   PASSWORD=Password123!               Login password
#
# Prerequisites:
#   brew install k6                     https://k6.io/docs/get-started/installation/
#   Stack running: cd observibility && ./deploy.sh
#
# Note: /api/payments/create-order may timeout (~5s) if Razorpay keys are not
# configured — this still generates load on the payment-service for dashboards.
#
#   Grafana:    http://localhost:3030   (Latency & Errors, Linkerd Golden Metrics)
#   Prometheus: http://localhost:9090
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_URL="${API_URL:-http://localhost:9080}"
K6_PROFILE="${K6_PROFILE:-rps100}"
CHAOS="${CHAOS:-0}"
SOAK_DURATION="${SOAK_DURATION:-10m}"
RPS_PER_SERVICE="${RPS_PER_SERVICE:-}"
TEST_DURATION="${TEST_DURATION:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${YELLOW}[load-test]${NC} $*"; }
ok()   { echo -e "${GREEN}[load-test]${NC} $*"; }
err()  { echo -e "${RED}[load-test]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[load-test] WARNING:${NC} $*"; }

usage() {
  head -n 40 "$0" | tail -n +2 | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rps20)       K6_PROFILE=rps20; shift ;;
    --rps50)       K6_PROFILE=rps50; shift ;;
    --rps100)      K6_PROFILE=rps100; shift ;;
    --rps200)      K6_PROFILE=rps200; shift ;;
    --rps100-soak) K6_PROFILE=rps100-soak; shift ;;
    --smoke)       K6_PROFILE=smoke; shift ;;
    --load)        K6_PROFILE=load; shift ;;
    --stress)      K6_PROFILE=stress; shift ;;
    --spike)       K6_PROFILE=spike; shift ;;
    --peak)        K6_PROFILE=peak; shift ;;
    --soak)        K6_PROFILE=soak; shift ;;
    --breakpoint)  K6_PROFILE=breakpoint; shift ;;
    --help|-h)     usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

rps_for_profile() {
  case "$K6_PROFILE" in
    rps20)         echo 20 ;;
    rps50)         echo 50 ;;
    rps100|rps100-soak) echo 100 ;;
    rps200)        echo 200 ;;
    *)             echo "${RPS_PER_SERVICE:-0}" ;;
  esac
}

duration_for_profile() {
  case "$K6_PROFILE" in
    rps20)         echo '30s' ;;
    rps50)         echo '5m' ;;
    rps100)        echo '5m' ;;
    rps200)        echo '3m' ;;
    rps100-soak)   echo '15m' ;;
    *)             echo "${TEST_DURATION:-custom}" ;;
  esac
}

profile_desc() {
  local rps duration journey total
  case "$K6_PROFILE" in
    rps20)
      echo '20 req/s per service × 30s (validation)'
      ;;
    rps50)
      echo '50 req/s per service × 5 min + journey (~250+ RPS total)'
      ;;
    rps100)
      echo '100 req/s per service × 5 min + journey (~500+ RPS total)'
      ;;
    rps200)
      echo '200 req/s per service × 3 min + journey (~1000+ RPS total)'
      ;;
    rps100-soak)
      echo '100 req/s per service × 15 min + journey (soak)'
      ;;
    smoke)      echo '5 VUs × 1 min' ;;
    load)       echo 'ramp to 50 VUs (5 min), sustain 50 VUs × 10 min, ramp down 2 min' ;;
    stress)     echo 'ramp to 200 VUs over 10 min, sustain 200 VUs × 10 min' ;;
    spike)      echo 'baseline 20 VUs → spike 300 VUs in 30s, hold 3 min' ;;
    peak)       echo 'ramp to 500 VUs (3 min), sustain 500 VUs × 5 min, ramp down 2 min' ;;
    soak)       echo "ramp to 30 VUs (2 min), sustain 30 VUs × ${SOAK_DURATION}, ramp down 2 min" ;;
    breakpoint) echo 'ramp 50→100→200→300→400→500 VUs (2 min each), then ramp down' ;;
    *)
      rps="$(rps_for_profile)"
      duration="${TEST_DURATION:-5m}"
      if [[ "$rps" != "0" ]]; then
        journey=$(( rps / 10 ))
        [[ "$journey" -lt 5 ]] && journey=5
        total=$(( rps * 5 + journey ))
        echo "${rps} req/s per service × ${duration} + journey (~${total}+ RPS total)"
      else
        echo 'custom'
      fi
      ;;
  esac
}

warn_kind_limits() {
  local rps=$1
  if [[ "$rps" -ge 200 ]]; then
    warn "rps200 targets ~1000+ total RPS — very aggressive for Kind single-node."
    warn "Expect pod OOM kills, elevated p99 latency, and threshold failures."
  elif [[ "$rps" -ge 100 ]]; then
    warn "100 req/s per service (~500+ total RPS) is heavy for a Kind single-node cluster."
    warn "You may see latency spikes, CPU throttling, and occasional 5xx errors."
    warn "k6 will scale up to 500+ VUs if response times are slow — watch node memory."
  elif [[ "$rps" -ge 50 ]]; then
    warn "50 req/s per service (~250+ RPS) — moderate load for local Kind."
  fi
  warn "Watch Grafana Golden Metrics: http://localhost:3030"
  warn "Filter by service tag: product-service, user-service, cart-service, order-service, payment-service"
}

if ! command -v k6 >/dev/null 2>&1; then
  err "k6 is not installed."
  err "Install with: brew install k6"
  err "Docs: https://k6.io/docs/get-started/installation/"
  exit 1
fi

RPS="$(rps_for_profile)"
if [[ "$K6_PROFILE" == rps* ]] || [[ -n "$RPS_PER_SERVICE" && "$RPS_PER_SERVICE" != "0" ]]; then
  [[ -z "$RPS_PER_SERVICE" ]] && RPS_PER_SERVICE="$RPS"
  [[ -z "$TEST_DURATION" ]] && TEST_DURATION="$(duration_for_profile)"
  warn_kind_limits "${RPS_PER_SERVICE:-100}"
fi

if [[ "$K6_PROFILE" == "peak" ]]; then
  warn "Peak profile uses 500 VUs — aggressive for a Kind single-node cluster."
  warn "Consider --rps100 for per-service RPS targeting instead."
fi

log "Checking API gateway at ${API_URL}/health ..."
if ! curl -sf --connect-timeout 5 "${API_URL}/health" >/dev/null; then
  err "API gateway not reachable at ${API_URL}"
  err "Start the stack first: cd observibility && ./deploy.sh"
  exit 1
fi
ok "API gateway is healthy"

log "Profile: ${K6_PROFILE} — $(profile_desc)"
log "Target:  ${API_URL}"
if [[ "$K6_PROFILE" == rps* ]] || [[ -n "$RPS_PER_SERVICE" ]]; then
  journey_rate=$(( (${RPS_PER_SERVICE:-100}) / 10 ))
  [[ "$journey_rate" -lt 5 ]] && journey_rate=5
  total_rps=$(( (${RPS_PER_SERVICE:-100}) * 5 + journey_rate ))
  log "RPS per service: ${RPS_PER_SERVICE:-100} | Duration: ${TEST_DURATION:-$(duration_for_profile)}"
  log "Expected total HTTP RPS: ~${total_rps} (5 services + journey)"
fi
if [[ "$CHAOS" == "1" ]]; then
  log "Chaos mode: thresholds relaxed (CHAOS=1)"
fi
log "Open Grafana: http://localhost:3030 while the test runs"
echo ""

export API_URL K6_PROFILE CHAOS SOAK_DURATION RPS_PER_SERVICE TEST_DURATION

k6 run "${SCRIPT_DIR}/k6-script.js"
exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
  ok "Load test finished successfully (profile: ${K6_PROFILE})"
else
  err "Load test exited with code ${exit_code} — check thresholds or gateway logs"
fi

exit $exit_code

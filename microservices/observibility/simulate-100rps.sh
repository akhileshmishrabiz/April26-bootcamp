#!/bin/bash
#
# Simulate ~100 requests/s aggregate through the API gateway.
#
# Unlike load-test/run-load-test.sh --rps100 (100 req/s per microservice,
# ~500+ total RPS), this script targets ~100 req/s combined via gateway
# endpoints that fan out to product, user, cart, order, and payment services.
#
# Scenarios: login, browse products, add to cart, checkout flow.
#
# Usage:
#   ./simulate-100rps.sh                     # 60s at 100 req/s
#   ./simulate-100rps.sh --duration 120        # 120 seconds
#   ./simulate-100rps.sh --rate 50             # 50 req/s aggregate
#   ./simulate-100rps.sh --curl-fallback       # force parallel curl loop
#
# Environment:
#   API_URL=http://localhost:9080
#   EMAIL=john.doe@example.com
#   PASSWORD=Password123!
#
# Prerequisites:
#   Stack running: cd observibility && ./deploy.sh
#   k6 (optional, preferred): brew install k6
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_URL="${API_URL:-http://localhost:9080}"
TARGET_RPS="${TARGET_RPS:-100}"
DURATION="${DURATION:-60}"
EMAIL="${EMAIL:-john.doe@example.com}"
PASSWORD="${PASSWORD:-Password123!}"
FORCE_CURL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration=*) DURATION="${1#*=}"; shift ;;
    --duration) DURATION="${2:-60}"; shift 2 ;;
    --rate=*) TARGET_RPS="${1#*=}"; shift ;;
    --rate) TARGET_RPS="${2:-100}"; shift 2 ;;
    --curl-fallback) FORCE_CURL=true; shift ;;
    --help|-h)
      head -n 25 "$0" | tail -n +2 | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${YELLOW}[100rps]${NC} $*"; }
ok()  { echo -e "${GREEN}[100rps]${NC} $*"; }
err() { echo -e "${RED}[100rps]${NC} $*" >&2; }

if ! curl -sf --connect-timeout 3 "$API_URL/health" >/dev/null; then
  err "API gateway not reachable at $API_URL"
  err "Start the stack first: cd observibility && ./deploy.sh"
  exit 1
fi

run_k6() {
  log "Running k6 gateway scenario: ${TARGET_RPS} req/s for ${DURATION}s → $API_URL"
  log "Open Grafana: http://localhost:3030 (Latency & Errors, Tracing & Logs)"
  echo ""
  export API_URL EMAIL PASSWORD TARGET_RPS TEST_DURATION="${DURATION}s"
  k6 run "${SCRIPT_DIR}/load-test/scenario-100rps.js"
}

run_curl_fallback() {
  log "k6 not found — using parallel curl loop at ~${TARGET_RPS} req/s for ${DURATION}s"
  local end=$((SECONDS + DURATION))
  local total=0 success=0 latency_sum=0
  local token=""
  local token_at=0
  local pids=()
  local interval
  interval="$(python3 -c "print(max(0.001, 1.0 / ${TARGET_RPS}))")"

  login_once() {
    curl -sf -X POST "$API_URL/api/users/login" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true
  }

  do_request() {
    local start end_ms code
    start=$(python3 -c 'import time; print(int(time.time()*1000))')
    case $((RANDOM % 10)) in
      0|1|2|3)
        code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/api/products?limit=5" || echo 000)
        ;;
      4)
        code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/api/users/login" \
          -H "Content-Type: application/json" \
          -d '{"email":"bad@example.com","password":"wrong"}' || echo 000)
        ;;
      5|6|7|8)
        if [[ -z "$token" ]] || [[ $((SECONDS - token_at)) -gt 120 ]]; then
          token=$(login_once)
          token_at=$SECONDS
        fi
        if [[ -n "$token" ]]; then
          local pid=$((1 + RANDOM % 15))
          curl -sf -X POST "$API_URL/api/cart/items" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "{\"productId\":$pid,\"quantity\":1}" >/dev/null 2>&1 || true
          code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/api/cart" \
            -H "Authorization: Bearer $token" || echo 000)
        else
          code=000
        fi
        ;;
      9)
        code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/health" || echo 000)
        ;;
    esac
    end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    echo "$code $((end_ms - start))"
  }

  while [[ $SECONDS -lt $end ]]; do
    while [[ ${#pids[@]} -ge 20 ]]; do
      wait -n 2>/dev/null || wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
    done
    (
      read -r code lat <<< "$(do_request)"
      echo "$code $lat"
    ) &
    pids+=($!)
    sleep "$interval"
  done

  for pid in "${pids[@]}"; do
    if read -r code lat <<< "$(wait "$pid" 2>/dev/null || echo "000 0")"; then
      total=$((total + 1))
      latency_sum=$((latency_sum + lat))
      if [[ "$code" =~ ^[23] ]]; then
        success=$((success + 1))
      fi
    fi
  done

  local avg=0 rate_pct=0
  [[ $total -gt 0 ]] && avg=$((latency_sum / total))
  [[ $total -gt 0 ]] && rate_pct=$(python3 -c "print(f'{$success/$total*100:.2f}')")

  echo ""
  echo "=== 100 RPS Gateway Simulation Summary (curl fallback) ==="
  echo "Target rate:     ${TARGET_RPS} req/s aggregate (via API gateway)"
  echo "Duration:        ${DURATION}s"
  echo "Total requests:  ${total}"
  echo "Success rate:    ${rate_pct}%"
  echo "Avg latency:     ${avg} ms"
  echo "==========================================================="
}

if [[ "$FORCE_CURL" == false ]] && command -v k6 >/dev/null 2>&1; then
  run_k6
else
  if [[ "$FORCE_CURL" == false ]]; then
    log "k6 not installed — falling back to parallel curl loop"
    log "Install k6 for accurate rate control: brew install k6"
  fi
  run_curl_fallback
fi

ok "Simulation finished"

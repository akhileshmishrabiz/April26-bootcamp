#!/bin/bash
#
# Simulate realistic e-commerce traffic against the API gateway.
# Generates metrics, logs, and traces for Grafana dashboards.
#
# Usage:
#   ./simulate-traffic.sh                    # 5 min, 2 req/s
#   ./simulate-traffic.sh --duration 600       # 10 minutes
#   ./simulate-traffic.sh --rate 5             # 5 req/s
#   ./simulate-traffic.sh --once               # single checkout flow
#

set -euo pipefail

API_URL="${API_URL:-http://localhost:9080}"
DURATION="${DURATION:-300}"
RATE="${RATE:-2}"
ONCE=false
EMAIL="${EMAIL:-john.doe@example.com}"
PASSWORD="${PASSWORD:-Password123!}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=true; shift ;;
    --duration=*) DURATION="${1#*=}"; shift ;;
    --duration) DURATION="${2:-300}"; shift 2 ;;
    --rate=*) RATE="${1#*=}"; shift ;;
    --rate) RATE="${2:-2}"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--once] [--duration SECS] [--rate REQ_PER_SEC]"
      echo "  API_URL=$API_URL"
      exit 0
      ;;
    *) shift ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${YELLOW}[traffic]${NC} $*"; }
ok()  { echo -e "${GREEN}[traffic]${NC} $*"; }
err() { echo -e "${RED}[traffic]${NC} $*" >&2; }

# --- helpers ---
json_field() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d$1)" 2>/dev/null || echo ""
}

login() {
  curl -sf -X POST "$API_URL/api/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))"
}

browse_products() {
  curl -sf "$API_URL/api/products?limit=5" >/dev/null
  local id=$((1 + RANDOM % 15))
  curl -sf "$API_URL/api/products/$id" >/dev/null || true
  curl -sf "$API_URL/api/products/search?q=phone" >/dev/null || true
  curl -sf "$API_URL/api/products/categories" >/dev/null || true
}

bad_login() {
  curl -sf -X POST "$API_URL/api/users/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"bad@example.com","password":"wrong"}' >/dev/null || true
}

cart_flow() {
  local token="$1"
  local product_id=$((1 + RANDOM % 15))
  curl -sf -X POST "$API_URL/api/cart/items" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"productId\":$product_id,\"quantity\":$((1 + RANDOM % 3))}" >/dev/null || true
  curl -sf "$API_URL/api/cart" -H "Authorization: Bearer $token" >/dev/null || true
}

checkout_flow() {
  local token="$1"
  cart_flow "$token"
  local order_resp
  order_resp=$(curl -sf -X POST "$API_URL/api/orders" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{"shippingAddress":"123 Simulated St, Test City"}' 2>/dev/null || echo '{}')
  local order_id
  order_id=$(echo "$order_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d.get('order_id','')))" 2>/dev/null || echo "")
  if [ -n "$order_id" ] && [ "$order_id" != "None" ]; then
    curl -sf -X POST "$API_URL/api/payments/create-order" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "{\"order_id\":\"$order_id\",\"amount\":99.99}" >/dev/null || true
  fi
  curl -sf "$API_URL/api/orders" -H "Authorization: Bearer $token" >/dev/null || true
}

health_checks() {
  curl -sf "$API_URL/health" >/dev/null
  for svc in product-service user-service cart-service order-service payment-service; do
    curl -sf "$API_URL/api/health/$svc" >/dev/null 2>&1 || true
  done
}

run_once() {
  log "Running single traffic cycle..."
  health_checks
  browse_products
  bad_login
  local token
  token=$(login || true)
  if [ -n "$token" ]; then
    cart_flow "$token"
    checkout_flow "$token"
    ok "Checkout flow completed"
  else
    err "Login failed — is seed data loaded?"
  fi
}

run_loop() {
  log "Simulating traffic for ${DURATION}s at ~${RATE} req/s → $API_URL"
  log "Open Grafana: http://localhost:3030 (Latency & Errors, Logs Explorer, Tracing dashboards)"
  local end=$((SECONDS + DURATION))
  local token=""
  local token_at=0

  while [ $SECONDS -lt $end ]; do
    case $((RANDOM % 10)) in
      0|1|2|3) browse_products ;;
      4)     bad_login ;;
      5|6)
        if [ -z "$token" ] || [ $((SECONDS - token_at)) -gt 120 ]; then
          token=$(login || true)
          token_at=$SECONDS
        fi
        if [ -n "$token" ]; then cart_flow "$token"; fi
        ;;
      7|8)
        if [ -z "$token" ] || [ $((SECONDS - token_at)) -gt 120 ]; then
          token=$(login || true)
          token_at=$SECONDS
        fi
        if [ -n "$token" ]; then checkout_flow "$token"; fi
        ;;
      9) health_checks ;;
    esac
    sleep "$(python3 -c "import random; print(round(random.expovariate($RATE), 3))")"
  done
  ok "Traffic simulation finished (${DURATION}s)"
}

# --- preflight ---
if ! curl -sf --connect-timeout 3 "$API_URL/health" >/dev/null; then
  err "API gateway not reachable at $API_URL"
  err "Start the stack first: cd observibility && ./deploy.sh"
  exit 1
fi

if [ "$ONCE" = true ]; then
  run_once
else
  run_loop
fi

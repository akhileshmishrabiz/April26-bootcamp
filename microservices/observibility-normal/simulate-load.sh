#!/usr/bin/env bash

set -uo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-ecommerce}"
DURATION_SECONDS="${DURATION_SECONDS:-900}"
REQUEST_INTERVAL_SECONDS="${REQUEST_INTERVAL_SECONDS:-0.5}"
STATUS_INTERVAL_SECONDS="${STATUS_INTERVAL_SECONDS:-30}"
HEALTH_INTERVAL_SECONDS="${HEALTH_INTERVAL_SECONDS:-15}"
REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-5}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
LOAD_USER_EMAIL="${LOAD_USER_EMAIL:-john.doe@example.com}"
LOAD_USER_PASSWORD="${LOAD_USER_PASSWORD:-Password123!}"
USER_AGENT="${USER_AGENT:-ecommerce-kind-load-simulator/1.0}"

SERVICES=(
  product-service
  user-service
  cart-service
  order-service
  payment-service
  notification-service
)

CONTEXT=""
TOKEN=""
PRODUCT_ID=""
PORT_FORWARD_PID=""
PORT_FORWARD_LOG=""
RESPONSE_FILE=""
RUN_STARTED=0
SUMMARY_PRINTED=0
START_TIME=0

TOTAL_REQUESTS=0
COUNT_2XX=0
COUNT_3XX=0
COUNT_4XX=0
COUNT_5XX=0
COUNT_TRANSPORT=0
COUNT_UNEXPECTED=0
HEALTH_SWEEPS=0
SCENARIOS=0

info() {
  printf '\n==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: ./observibility-normal/simulate-load.sh

Runs bounded traffic against the helm-ms-simple e-commerce app.

Common environment variables:
  DURATION_SECONDS           Run length (default: 900)
  REQUEST_INTERVAL_SECONDS   Delay between scenarios (default: 0.5)
  STATUS_INTERVAL_SECONDS    Progress interval (default: 30)
  HEALTH_INTERVAL_SECONDS    Six-service health sweep interval (default: 15)
  GATEWAY_URL                Preferred gateway (default: http://localhost:8080)
  LOAD_USER_EMAIL            Seeded login email
  LOAD_USER_PASSWORD         Seeded login password

The script locates the correct Kind context and manages a fallback port-forward.
EOF
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "'$1' is required."
}

is_non_negative_number() {
  python3 - "$1" <<'PY'
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if value >= 0 else 1)
PY
}

is_positive_number() {
  python3 - "$1" <<'PY'
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if value > 0 else 1)
PY
}

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) [[ "$1" -gt 0 ]] ;;
  esac
}

context_exists() {
  kubectl config get-contexts "$1" -o name 2>/dev/null | grep -Fxq "$1"
}

cluster_has_app() {
  local context="$1"
  kubectl --context "$context" get namespace "$APP_NAMESPACE" >/dev/null 2>&1 &&
    kubectl --context "$context" -n "$APP_NAMESPACE" get service/api-gateway >/dev/null 2>&1
}

find_context() {
  local cluster context
  local -a clusters=()
  local -a candidates=()

  while IFS= read -r cluster; do
    [[ -n "$cluster" ]] && clusters+=("$cluster")
  done < <(kind get clusters 2>/dev/null)

  ((${#clusters[@]} > 0)) ||
    fail "No Kind clusters found. Deploy helm-ms-simple first."

  for cluster in "${clusters[@]}"; do
    [[ "$cluster" == "ecommerce-ms-simple" ]] && candidates+=("$cluster")
  done
  for cluster in "${clusters[@]}"; do
    [[ "$cluster" != "ecommerce-ms-simple" ]] && candidates+=("$cluster")
  done

  for cluster in "${candidates[@]}"; do
    context="kind-${cluster}"
    context_exists "$context" || continue
    if cluster_has_app "$context"; then
      printf '%s\n' "$context"
      return 0
    fi
  done

  fail "No Kind cluster contains namespace '$APP_NAMESPACE' and service/api-gateway."
}

record_status() {
  local status="$1"
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
  case "$status" in
    2??) COUNT_2XX=$((COUNT_2XX + 1)) ;;
    3??) COUNT_3XX=$((COUNT_3XX + 1)) ;;
    4??) COUNT_4XX=$((COUNT_4XX + 1)) ;;
    5??) COUNT_5XX=$((COUNT_5XX + 1)) ;;
    *) COUNT_TRANSPORT=$((COUNT_TRANSPORT + 1)) ;;
  esac
}

LAST_STATUS=""
LAST_BODY=""
request() {
  local method="$1"
  local path="$2"
  local expected="${3:-2[0-9][0-9]}"
  local body="${4:-}"
  local auth_mode="${5:-none}"
  local status
  local -a args=(
    -sS
    -o "$RESPONSE_FILE"
    -w "%{http_code}"
    --max-time "$REQUEST_TIMEOUT_SECONDS"
    -X "$method"
    -H "Accept: application/json"
    -H "User-Agent: $USER_AGENT"
    -H "X-Load-Simulation: kind-lab"
  )

  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" --data "$body")
  fi
  case "$auth_mode" in
    valid)
      [[ -n "$TOKEN" ]] || return 2
      args+=(-H "Authorization: Bearer $TOKEN")
      ;;
    invalid)
      args+=(-H "Authorization: Bearer intentionally-invalid")
      ;;
  esac

  status="$(curl "${args[@]}" "${GATEWAY_URL}${path}" 2>/dev/null)" || status="000"
  LAST_STATUS="$status"
  LAST_BODY="$(cat "$RESPONSE_FILE" 2>/dev/null || true)"
  record_status "$status"

  if [[ ! "$status" =~ ^(${expected})$ ]]; then
    COUNT_UNEXPECTED=$((COUNT_UNEXPECTED + 1))
  fi
  return 0
}

gateway_is_ready() {
  curl -fsS --max-time 2 "${GATEWAY_URL}/health" >/dev/null 2>&1
}

find_free_port() {
  python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

start_port_forward() {
  local port attempt
  port="$(find_free_port)" || fail "Could not allocate a local port."
  PORT_FORWARD_LOG="$(mktemp -t ecommerce-load-port-forward.XXXXXX)" ||
    fail "Could not create a temporary port-forward log."

  info "Gateway at '$GATEWAY_URL' is unavailable; starting a managed port-forward"
  kubectl --context "$CONTEXT" -n "$APP_NAMESPACE" port-forward \
    --address 127.0.0.1 service/api-gateway "${port}:80" \
    >"$PORT_FORWARD_LOG" 2>&1 &
  PORT_FORWARD_PID=$!
  GATEWAY_URL="http://127.0.0.1:${port}"

  for attempt in $(seq 1 30); do
    if gateway_is_ready; then
      printf 'Using managed gateway: %s\n' "$GATEWAY_URL"
      return 0
    fi
    if ! kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
      warn "kubectl port-forward exited before becoming ready."
      [[ -s "$PORT_FORWARD_LOG" ]] && cat "$PORT_FORWARD_LOG" >&2
      fail "Could not reach service/api-gateway."
    fi
    sleep 0.5
  done

  fail "Timed out waiting for the managed gateway port-forward."
}

print_summary() {
  local now elapsed
  [[ "$RUN_STARTED" -eq 1 && "$SUMMARY_PRINTED" -eq 0 ]] || return 0
  SUMMARY_PRINTED=1
  now="$(date +%s)"
  elapsed=$((now - START_TIME))
  printf '\nLoad simulation summary\n'
  printf '  Context:             %s\n' "$CONTEXT"
  printf '  Runtime:             %ss\n' "$elapsed"
  printf '  Scenarios:           %s\n' "$SCENARIOS"
  printf '  Health sweeps:       %s\n' "$HEALTH_SWEEPS"
  printf '  Total HTTP attempts: %s\n' "$TOTAL_REQUESTS"
  printf '  Responses:           2xx=%s 3xx=%s 4xx=%s 5xx=%s transport=%s\n' \
    "$COUNT_2XX" "$COUNT_3XX" "$COUNT_4XX" "$COUNT_5XX" "$COUNT_TRANSPORT"
  printf '  Unexpected statuses: %s\n' "$COUNT_UNEXPECTED"
}

cleanup() {
  print_summary
  if [[ -n "$PORT_FORWARD_PID" ]] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
    kill "$PORT_FORWARD_PID" 2>/dev/null || true
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
  [[ -z "$PORT_FORWARD_LOG" ]] || rm -f "$PORT_FORWARD_LOG"
  [[ -z "$RESPONSE_FILE" ]] || rm -f "$RESPONSE_FILE"
}

handle_signal() {
  printf '\nStopping load simulation on %s...\n' "$1"
  exit 130
}

trap cleanup EXIT
trap 'handle_signal Ctrl+C' INT
trap 'handle_signal SIGTERM' TERM

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    fail "This script accepts configuration through environment variables, not arguments."
    ;;
esac

health_sweep() {
  local service
  for service in "${SERVICES[@]}"; do
    request GET "/api/health/${service}" "200"
  done
  HEALTH_SWEEPS=$((HEALTH_SWEEPS + 1))
}

load_identity() {
  local login_body
  login_body="$(python3 - "$LOAD_USER_EMAIL" "$LOAD_USER_PASSWORD" <<'PY'
import json
import sys
print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))
PY
)"
  request POST "/api/users/login" "200|401" "$login_body"
  if [[ "$LAST_STATUS" == "200" ]]; then
    TOKEN="$(printf '%s' "$LAST_BODY" | python3 -c \
      'import json,sys; print(json.load(sys.stdin).get("token", ""))' 2>/dev/null || true)"
  fi

  if [[ -z "$TOKEN" ]]; then
    warn "Seeded-user login failed; authenticated business scenarios will be skipped."
    warn "Seed the app or set LOAD_USER_EMAIL and LOAD_USER_PASSWORD."
  else
    printf 'Authenticated as %s (token retained in memory only).\n' "$LOAD_USER_EMAIL"
  fi
}

load_product_id() {
  request GET "/api/products?page_size=20&is_active=true" "200"
  if [[ "$LAST_STATUS" == "200" ]]; then
    PRODUCT_ID="$(printf '%s' "$LAST_BODY" | python3 -c \
      'import json,sys; data=json.load(sys.stdin); products=data.get("products", []); print(products[0].get("id", "") if products else "")' \
      2>/dev/null || true)"
  fi
  [[ -n "$PRODUCT_ID" ]] ||
    warn "No active seeded product found; cart scenarios will be skipped."
}

run_scenario() {
  local choice="$1"
  case "$choice" in
    0) request GET "/api/products?page_size=12" "200" ;;
    1) request GET "/api/products/search?q=phone" "200" ;;
    2) request GET "/api/products/categories" "200" ;;
    3) request GET "/api/products/999999999" "404" ;;
    4) request GET "/api/products/search" "400" ;;
    5) request POST "/api/users/login" "400" '{"email":"not-an-email","password":""}' ;;
    6) request GET "/api/users/profile" "401" "" invalid ;;
    7)
      if [[ -n "$TOKEN" ]]; then
        request GET "/api/users/profile" "200" "" valid
      else
        request GET "/api/users/profile" "401" "" invalid
      fi
      ;;
    8)
      if [[ -n "$TOKEN" ]]; then
        request GET "/api/cart" "200" "" valid
      else
        request GET "/api/cart" "401" "" invalid
      fi
      ;;
    9)
      if [[ -n "$TOKEN" && -n "$PRODUCT_ID" ]]; then
        request POST "/api/cart/items" "201" \
          "{\"productId\":${PRODUCT_ID},\"quantity\":1}" valid
        request GET "/api/cart" "200" "" valid
        request DELETE "/api/cart/items/${PRODUCT_ID}" "200|404" "" valid
      else
        request POST "/api/cart/items" "401" '{"productId":1,"quantity":1}' invalid
      fi
      ;;
    10)
      if [[ -n "$TOKEN" ]]; then
        request GET "/api/orders" "200" "" valid
      else
        request GET "/api/orders" "401" "" invalid
      fi
      ;;
    11)
      if [[ -n "$TOKEN" ]]; then
        request POST "/api/orders" "400" '{}' valid
      else
        request POST "/api/orders" "401" '{}' invalid
      fi
      ;;
    12)
      if [[ -n "$TOKEN" ]]; then
        request GET "/api/payments/order/load-simulation-missing" "404" "" valid
      else
        request GET "/api/payments/order/load-simulation-missing" "401" "" invalid
      fi
      ;;
    13)
      if [[ -n "$TOKEN" ]]; then
        request POST "/api/payments/verify" "400" '{}' valid
      else
        request POST "/api/payments/verify" "401" '{}' invalid
      fi
      ;;
    14) request GET "/api/products/category/Electronics" "200" ;;
    *) request GET "/api/does-not-exist" "404" ;;
  esac
}

info "Checking prerequisites and configuration"
require_command kind
require_command kubectl
require_command curl
require_command python3
require_command grep
require_command seq
is_positive_integer "$DURATION_SECONDS" ||
  fail "DURATION_SECONDS must be a positive integer."
is_non_negative_number "$REQUEST_INTERVAL_SECONDS" ||
  fail "REQUEST_INTERVAL_SECONDS must be a non-negative number."
is_positive_number "$REQUEST_TIMEOUT_SECONDS" ||
  fail "REQUEST_TIMEOUT_SECONDS must be a positive number."
is_positive_integer "$STATUS_INTERVAL_SECONDS" ||
  fail "STATUS_INTERVAL_SECONDS must be a positive integer."
is_positive_integer "$HEALTH_INTERVAL_SECONDS" ||
  fail "HEALTH_INTERVAL_SECONDS must be a positive integer."

info "Locating the Kind cluster containing '$APP_NAMESPACE'"
CONTEXT="$(find_context)" || exit $?
kubectl --context "$CONTEXT" cluster-info >/dev/null 2>&1 ||
  fail "Kubernetes API for '$CONTEXT' is unavailable."
printf 'Selected context: %s\n' "$CONTEXT"

info "Validating all backend deployments"
for service in "${SERVICES[@]}"; do
  kubectl --context "$CONTEXT" -n "$APP_NAMESPACE" get "deployment/${service}" >/dev/null 2>&1 ||
    fail "Missing deployment/${service} in namespace '$APP_NAMESPACE'."
  kubectl --context "$CONTEXT" -n "$APP_NAMESPACE" rollout status \
    "deployment/${service}" --timeout=90s >/dev/null ||
    fail "deployment/${service} is not available."
  printf 'Ready: %s\n' "$service"
done
kubectl --context "$CONTEXT" -n "$APP_NAMESPACE" rollout status \
  deployment/api-gateway --timeout=90s >/dev/null ||
  fail "deployment/api-gateway is not available."

RESPONSE_FILE="$(mktemp -t ecommerce-load-response.XXXXXX)" ||
  fail "Could not create a temporary response file."
if ! gateway_is_ready; then
  start_port_forward
else
  printf 'Using gateway: %s\n' "$GATEWAY_URL"
fi

info "Validating service health and seed data"
health_sweep
[[ "$COUNT_UNEXPECTED" -eq 0 ]] ||
  fail "One or more service health endpoints did not return HTTP 200."
load_identity
load_product_id

# Preflight requests prove availability but are excluded from the timed run.
TOTAL_REQUESTS=0
COUNT_2XX=0
COUNT_3XX=0
COUNT_4XX=0
COUNT_5XX=0
COUNT_TRANSPORT=0
COUNT_UNEXPECTED=0
HEALTH_SWEEPS=0

START_TIME="$(date +%s)"
RUN_STARTED=1
END_TIME=$((START_TIME + DURATION_SECONDS))
NEXT_STATUS=$((START_TIME + STATUS_INTERVAL_SECONDS))
NEXT_HEALTH="$START_TIME"

info "Generating traffic for ${DURATION_SECONDS}s"
printf 'Request interval: %ss; health sweep interval: %ss\n' \
  "$REQUEST_INTERVAL_SECONDS" "$HEALTH_INTERVAL_SECONDS"

while [[ "$(date +%s)" -lt "$END_TIME" ]]; do
  now="$(date +%s)"

  if [[ "$now" -ge "$NEXT_HEALTH" ]]; then
    health_sweep
    NEXT_HEALTH=$((now + HEALTH_INTERVAL_SECONDS))
  fi

  run_scenario $((SCENARIOS % 16))
  SCENARIOS=$((SCENARIOS + 1))

  if [[ "$now" -ge "$NEXT_STATUS" ]]; then
    printf '[%4ss] scenarios=%s requests=%s 2xx=%s 4xx=%s 5xx=%s transport=%s unexpected=%s\n' \
      "$((now - START_TIME))" "$SCENARIOS" "$TOTAL_REQUESTS" "$COUNT_2XX" \
      "$COUNT_4XX" "$COUNT_5XX" "$COUNT_TRANSPORT" "$COUNT_UNEXPECTED"
    NEXT_STATUS=$((now + STATUS_INTERVAL_SECONDS))
  fi

  sleep "$REQUEST_INTERVAL_SECONDS"
done

exit 0

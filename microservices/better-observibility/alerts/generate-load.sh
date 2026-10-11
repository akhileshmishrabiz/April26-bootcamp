#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-ecommerce}"
LOCAL_PORT="${LOCAL_PORT:-18001}"
DURATION_SECONDS="${DURATION_SECONDS:-150}"
WORKERS="${WORKERS:-15}"
URL="http://127.0.0.1:${LOCAL_PORT}/health"
PF_LOG="$(mktemp)"

cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
    wait "$PF_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$PF_LOG"
}
trap cleanup EXIT INT TERM

command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }

kubectl -n "$APP_NAMESPACE" get service product-service >/dev/null
kubectl -n "$APP_NAMESPACE" port-forward \
  service/product-service "${LOCAL_PORT}:8001" >"$PF_LOG" 2>&1 &
PF_PID=$!

for _ in {1..30}; do
  if curl --silent --fail --max-time 1 "$URL" >/dev/null; then
    break
  fi
  if ! kill -0 "$PF_PID" >/dev/null 2>&1; then
    cat "$PF_LOG"
    exit 1
  fi
  sleep 1
done

curl --silent --fail --max-time 2 "$URL" >/dev/null || {
  echo "Could not reach product-service through the port-forward."
  cat "$PF_LOG"
  exit 1
}

echo "Generating traffic against product-service for ${DURATION_SECONDS}s..."
echo "This should fire EcommerceHighRequestRate after roughly 1-2 minutes."

END_TIME=$((SECONDS + DURATION_SECONDS))
for ((worker = 1; worker <= WORKERS; worker++)); do
  (
    while ((SECONDS < END_TIME)); do
      curl --silent --output /dev/null --max-time 2 "$URL" || true
      sleep 0.2
    done
  ) &
done
wait

echo
echo "Load generation finished."
echo "Check Prometheus alerts and the Mailpit inbox. A resolved email follows after the request rate falls."

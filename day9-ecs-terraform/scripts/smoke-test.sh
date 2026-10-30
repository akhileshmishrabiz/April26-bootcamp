#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-ecs-day9:local}"
CONTAINER_NAME="day9-smoke-${RANDOM}-$$"
HOST_PORT="${SMOKE_TEST_PORT:-8080}"
BASE_URL="http://127.0.0.1:${HOST_PORT}"

cleanup() {
  status=$?
  if (( status != 0 )); then
    echo "Smoke test failed; container logs follow:" >&2
    docker logs "${CONTAINER_NAME}" >&2 || true
  fi
  docker rm --force "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting container ${CONTAINER_NAME} from image ${IMAGE} on port ${HOST_PORT}..."
docker run --detach \
  --name "${CONTAINER_NAME}" \
  --publish "127.0.0.1:${HOST_PORT}:8000" \
  "${IMAGE}" >/dev/null

echo "Waiting for application to become healthy at ${BASE_URL}/health..."
for attempt in {1..30}; do
  if curl --fail --silent "${BASE_URL}/health" > /tmp/day9-health.json 2>/dev/null; then
    break
  fi

  if (( attempt == 30 )); then
    echo "Application did not become healthy within 30 seconds." >&2
    exit 1
  fi
  sleep 1
done

python3 - /tmp/day9-health.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)

assert payload.get("status") == "healthy", f"Expected status healthy, got {payload}"
assert payload.get("database") == "connected", f"Expected database connected, got {payload}"
print(f"Healthcheck passed: {payload}")
PY

echo "Checking /metrics endpoint..."
curl --fail --silent --show-error "${BASE_URL}/metrics" | grep -q "http_requests_total"
echo "Metrics endpoint passed."

echo "Checking /login endpoint..."
curl --fail --silent --show-error "${BASE_URL}/login" | grep -q "Password"
echo "Login route verification passed."

echo "All Day 9 container smoke tests passed successfully!"

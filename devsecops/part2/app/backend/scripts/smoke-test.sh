#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-devops-quest-backend:local}"
RUN_ID="${RANDOM}-$$"
APP_CONTAINER="devops-quest-backend-smoke-${RUN_ID}"
DB_CONTAINER="devops-quest-db-smoke-${RUN_ID}"
NETWORK="devops-quest-smoke-${RUN_ID}"
HOST_PORT="${SMOKE_TEST_PORT:-5080}"
BASE_URL="http://127.0.0.1:${HOST_PORT}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  status=$?
  if (( status != 0 )); then
    echo "Smoke test failed; backend container logs follow:" >&2
    docker logs "${APP_CONTAINER}" >&2 || true
  fi
  docker rm --force "${APP_CONTAINER}" "${DB_CONTAINER}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK}" >/dev/null 2>&1 || true
  rm -f "${RESPONSE_FILE}"
}
trap cleanup EXIT

docker network create "${NETWORK}" >/dev/null
docker run --detach \
  --name "${DB_CONTAINER}" \
  --network "${NETWORK}" \
  --env POSTGRES_DB=devops_learning \
  --env POSTGRES_PASSWORD=postgres \
  postgres:16-alpine >/dev/null

docker run --detach \
  --name "${APP_CONTAINER}" \
  --network "${NETWORK}" \
  --publish "127.0.0.1:${HOST_PORT}:8000" \
  --env "DATABASE_URL=postgresql://postgres:postgres@${DB_CONTAINER}:5432/devops_learning" \
  "${IMAGE}" >/dev/null

for attempt in {1..60}; do
  if curl --fail --silent --show-error "${BASE_URL}/health" > "${RESPONSE_FILE}" 2>/dev/null; then
    break
  fi
  if (( attempt == 60 )); then
    echo "Backend did not become healthy within 60 seconds." >&2
    exit 1
  fi
  sleep 1
done

python3 - "${RESPONSE_FILE}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)

assert payload == {"status": "healthy", "database": "connected"}, payload
PY

curl --fail --silent --show-error "${BASE_URL}/api" > "${RESPONSE_FILE}"
python3 - "${RESPONSE_FILE}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)

assert payload["status"] == "healthy", payload
assert payload["message"] == "API is operational", payload
PY

echo "Backend health and core API smoke checks passed."

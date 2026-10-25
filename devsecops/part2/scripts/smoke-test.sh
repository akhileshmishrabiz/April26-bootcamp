#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-devops-quest:local}"
CONTAINER_NAME="devops-quest-smoke-${RANDOM}-$$"
HOST_PORT="${SMOKE_TEST_PORT:-5080}"
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

docker run --detach \
  --name "${CONTAINER_NAME}" \
  --publish "127.0.0.1:${HOST_PORT}:5000" \
  "${IMAGE}" >/dev/null

for attempt in {1..30}; do
  if curl --fail --silent "${BASE_URL}/health" > /tmp/devops-quest-health.json 2>/dev/null; then
    break
  fi

  if (( attempt == 30 )); then
    echo "Application did not become healthy within 30 seconds." >&2
    exit 1
  fi
  sleep 1
done

python3 - /tmp/devops-quest-health.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)

assert payload["status"] == "ok", payload
assert payload["service"] == "devops-quest", payload
PY

curl --fail --silent --show-error \
  "${BASE_URL}/api/challenges?player_id=1" > /tmp/devops-quest-challenges.json

python3 - /tmp/devops-quest-challenges.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    challenges = json.load(response)

assert len(challenges) == 8, challenges
assert all("answer" not in challenge for challenge in challenges), challenges
assert any(challenge["slug"] == "docker-detective" for challenge in challenges)
PY

curl --fail --silent --show-error \
  --request POST \
  --header "Content-Type: application/json" \
  --data '{"player_id":1,"answer":"USER"}' \
  "${BASE_URL}/api/challenges/docker-detective/submit" \
  > /tmp/devops-quest-answer.json

python3 - /tmp/devops-quest-answer.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    result = json.load(response)

assert result["correct"] is True, result
assert result["earned_xp"] == 40, result
PY

echo "Container health and core API smoke checks passed."

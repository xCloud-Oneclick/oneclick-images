#!/usr/bin/env bash
# Boot the image in local-store mode, check liveness, the UI and the authenticated API, create a
# dataset, restart, and check the dataset is still listed.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=250

user=$(docker image inspect -f '{{.Config.User}}' "$IMAGE")
[ "$user" = "65532:65532" ] || { echo "expected user 65532:65532, got '$user'" >&2; exit 1; }

tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
app="parseable-app-$tag"; vol="parseable-data-$tag"; stg="parseable-stg-$tag"
pw=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')

cleanup() {
  docker logs "$app" 2>&1 | tail -n 50 || true
  docker rm -f "$app" >/dev/null 2>&1 || true
  docker volume rm "$vol" "$stg" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$vol" >/dev/null
docker volume create "$stg" >/dev/null
docker run -d --name "$app" -p 8000 -v "$vol:/data" -v "$stg:/staging" \
  -e P_USERNAME=admin -e "P_PASSWORD=$pw" "$IMAGE" >/dev/null

port() { docker port "$app" 8000/tcp | head -n1 | sed 's/.*://'; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@" 2>/dev/null || echo 0; }
expect() { # description expected actual
  [ "$2" = "$3" ] || { echo "$1: expected HTTP $2, got $3" >&2; exit 1; }
}

wait_ready() {
  for _ in $(seq 1 60); do
    [ "$(code "http://localhost:$(port)/api/v1/liveness")" = 200 ] && return 0
    sleep 2
  done
  echo "app never became ready" >&2
  return 1
}

check() {
  local base="http://localhost:$(port)"
  expect "GET /api/v1/liveness" 200 "$(code "$base/api/v1/liveness")"
  expect "GET / (console UI)" 200 "$(code "$base/")"
  expect "GET /api/v1/about without credentials" 401 "$(code "$base/api/v1/about")"
  expect "GET /api/v1/about with credentials" 200 "$(code -u "admin:$pw" "$base/api/v1/about")"
}

wait_ready
check
base="http://localhost:$(port)"
expect "PUT /api/v1/logstream/smoke" 200 "$(code -u "admin:$pw" -X PUT "$base/api/v1/logstream/smoke")"
curl -s --max-time 5 -u "admin:$pw" "$base/api/v1/logstream" | grep -q '"smoke"' \
  || { echo "dataset 'smoke' is not listed after creation" >&2; exit 1; }

health=$(docker inspect -f '{{.State.Health.Status}}' "$app")
for _ in $(seq 1 20); do
  health=$(docker inspect -f '{{.State.Health.Status}}' "$app")
  [ "$health" = healthy ] && break
  sleep 5
done
[ "$health" = healthy ] || { echo "container health is '$health', expected healthy" >&2; exit 1; }

docker restart "$app" >/dev/null
wait_ready
check
base="http://localhost:$(port)"
curl -s --max-time 5 -u "admin:$pw" "$base/api/v1/logstream" | grep -q '"smoke"' \
  || { echo "dataset 'smoke' is missing after restart" >&2; exit 1; }
size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }
echo "ok: $IMAGE"

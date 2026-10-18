#!/usr/bin/env bash
# Boot the image, check the app shell, assets and 404 handling, restart, check again.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=30

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }

uid=$(docker run --rm --entrypoint id "$IMAGE" -u)
[ "$uid" != 0 ] || { echo "image runs as root" >&2; exit 1; }

# Same gate as the publish workflow, so a vulnerable base fails at the pull request.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/aquasecurity/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa \
  image --quiet --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE"

tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
app="keeweb-app-$tag"

cleanup() {
  docker logs "$app" 2>&1 | tail -n 50 || true
  docker rm -f "$app" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Prints the HTTP status of GET <path> issued from inside the container.
status() {
  docker exec "$app" wget -S -q -O /dev/null "http://localhost:8080$1" 2>&1 | awk '/HTTP\//{c=$2} END{print c+0}' || true
}

wait_ready() {
  for _ in $(seq 1 30); do
    [ "$(status /)" = 200 ] && return 0
    sleep 1
  done
  echo "app never became ready" >&2
  return 1
}

check() {
  local when=$1
  [ "$(status /)" = 200 ] || { echo "/ is not 200 $when (got $(status /))" >&2; exit 1; }
  [ "$(status /manifest.json)" = 200 ] || { echo "/manifest.json is not 200 $when" >&2; exit 1; }
  [ "$(status /service-worker.js)" = 200 ] || { echo "/service-worker.js is not 200 $when" >&2; exit 1; }
  [ "$(status /no-such-file)" = 404 ] || { echo "/no-such-file is not 404 $when (got $(status /no-such-file))" >&2; exit 1; }
  docker exec "$app" wget -q -O - http://localhost:8080/ | grep -q '<title>KeeWeb' \
    || { echo "index page has no KeeWeb title $when" >&2; exit 1; }
}

docker run -d --name "$app" "$IMAGE" >/dev/null
wait_ready
check "after start"

docker restart "$app" >/dev/null
wait_ready
check "after restart"
echo "ok: $IMAGE"

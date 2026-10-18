#!/usr/bin/env bash
# Boot the image (database-less mode, as upstream builds it), check /api/ping and /, restart, check again.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=230

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }

tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
app="sqlchat-app-$tag"

cleanup() {
  docker logs "$app" 2>&1 | tail -n 50 || true
  docker rm -f "$app" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if docker run --rm --entrypoint sh "$IMAGE" -c 'command -v npm' >/dev/null 2>&1; then
  echo "npm must not be present in the runtime image" >&2
  exit 1
fi
# Same gate as the publish workflow, so a vulnerable base fails at the pull request.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/aquasecurity/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa \
  image --quiet --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE"

# Prints "<status> <body prefix>" of GET <path> issued from inside the app container.
get() {
  docker exec "$app" node -e "fetch('http://localhost:3000$1').then(async r=>console.log(r.status, (await r.text()).slice(0,30000).replace(/\s+/g,' '))).catch(e=>console.log(0, String(e)))"
}

wait_ready() {
  for _ in $(seq 1 60); do
    case "$(get /api/ping 2>/dev/null || echo 0)" in "200 "*) return 0 ;; esac
    sleep 2
  done
  echo "app never became ready" >&2
  return 1
}

check() {
  local out
  out=$(get /api/ping)
  [[ "$out" == "200 Hello world!" ]] || { echo "/api/ping: expected '200 Hello world!', got: ${out:0:200}" >&2; exit 1; }
  out=$(get /)
  [[ "$out" == "200 "* && "$out" == *"SQL Chat"* ]] \
    || { echo "/: expected 200 with 'SQL Chat' in body, got: ${out:0:300}" >&2; exit 1; }
}

docker run -d --name "$app" "$IMAGE" >/dev/null
wait_ready
check
[ "$(docker inspect -f '{{.Config.User}}' "$app")" = node ] || { echo "container must run as user node" >&2; exit 1; }

docker restart "$app" >/dev/null
wait_ready
check
echo "ok: $IMAGE"

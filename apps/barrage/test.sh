#!/usr/bin/env bash
# Boot the image, confirm GET / 500s without NEXTAUTH_SECRET (the upstream README's documented
# required env, missing session secret makes unstable_getServerSession throw during SSR of the
# login page), then boot it with the full documented env and confirm GET / is healthy. Restart
# and check again.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=450

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }

if docker run --rm --entrypoint sh "$IMAGE" -c 'command -v npm' >/dev/null 2>&1; then
  echo "npm must not be present in the runtime image" >&2
  exit 1
fi
# Same gate as the publish workflow, so a vulnerable base fails at the pull request.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/aquasecurity/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa \
  image --quiet --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE"

tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
nosec="barrage-nosecret-$tag"
app="barrage-app-$tag"
secret=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
pw=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

cleanup() {
  docker logs "$app" 2>&1 | tail -n 40 || true
  docker rm -f "$nosec" "$app" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Prints the HTTP status of GET <path> issued from inside the given container.
status() {
  docker exec "$1" node -e "fetch('http://localhost:3000$2',{redirect:'manual'}).then(r=>console.log(r.status)).catch(()=>console.log(0))"
}

wait_up() {
  for _ in $(seq 1 30); do
    [ "$(status "$1" / 2>/dev/null || echo 0)" != 0 ] && return 0
    sleep 2
  done
  echo "app never responded" >&2
  return 1
}

# 1. Without NEXTAUTH_SECRET, next-auth's unstable_getServerSession throws during the index
#    page's getServerSideProps: this is the 500 the node-22-lts branch left unexplained.
docker run -d --name "$nosec" "$IMAGE" >/dev/null
wait_up "$nosec"
[ "$(status "$nosec" /)" = 500 ] || { echo "expected / to 500 without NEXTAUTH_SECRET (root cause changed?)" >&2; exit 1; }
docker rm -f "$nosec" >/dev/null

# 2. With the full env the upstream README documents, GET / must serve the login page.
docker run -d --name "$app" \
  -e NEXTAUTH_SECRET="$secret" \
  -e NEXTAUTH_URL=http://localhost:3000 \
  -e DELUGE_URL=http://deluge.invalid:8112 \
  -e DELUGE_PASSWORD=deluge-pw \
  -e BARRAGE_PASSWORD="$pw" \
  "$IMAGE" >/dev/null
wait_up "$app"
[ "$(status "$app" /)" = 200 ] || { echo "/ is not 200 with NEXTAUTH_SECRET set" >&2; exit 1; }

docker restart "$app" >/dev/null
wait_up "$app"
[ "$(status "$app" /)" = 200 ] || { echo "/ is not 200 after restart" >&2; exit 1; }
echo "ok: $IMAGE"

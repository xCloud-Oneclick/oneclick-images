#!/usr/bin/env bash
# Boot the image, check the setup status API and the front page, check the workerd sandbox binary,
# write a marker to the data volume, recreate the container on the same volume and read it back.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=950

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
uid=$(docker run --rm --entrypoint id "$IMAGE" -u)
[ "$uid" != 0 ] || { echo "image runs as root (uid $uid)" >&2; exit 1; }

tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
app="emdash-app-$tag"
vol="emdash-data-$tag"
envfile=$(mktemp)
statusfile=$(mktemp)
printf 'EMDASH_ENCRYPTION_KEY_HEX=%s\nEMDASH_SITE_URL=http://localhost:4321\n' \
  "$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')" >"$envfile"

cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "--- last 50 log lines of $app" >&2
    docker logs "$app" 2>&1 | tail -n 50 >&2 || true
  fi
  docker rm -f "$app" >/dev/null 2>&1 || true
  docker volume rm "$vol" >/dev/null 2>&1 || true
  rm -f "$envfile" "$statusfile"
}
trap cleanup EXIT

start() {
  docker run -d --name "$app" --env-file "$envfile" -p 4321 -v "$vol:/app/data" "$IMAGE" >/dev/null
}

# The published host port changes when the container is recreated, so resolve it on every call.
wait_ready() {
  local code=none
  for _ in $(seq 1 60); do
    base="http://localhost:$(docker port "$app" 4321/tcp | head -n1 | sed 's/.*://')"
    code=$(curl -s -o "$statusfile" -w '%{http_code}' "$base/_emdash/api/setup/status" || true)
    if [ "$code" = 200 ]; then
      jq -e 'type == "object"' "$statusfile" >/dev/null \
        || { echo "GET /_emdash/api/setup/status expected a JSON object, got: $(head -c 300 "$statusfile")" >&2; return 1; }
      return 0
    fi
    sleep 2
  done
  echo "GET /_emdash/api/setup/status expected 200, last status $code" >&2
  return 1
}

start
wait_ready

# Front page renders the seeded blog through the server and the database.
code=$(curl -s -o /dev/null -w '%{http_code}' "$base/")
[ "$code" = 200 ] || { echo "GET / expected 200, got $code" >&2; exit 1; }

# The image architecture must match the one the node binary reports, and the workerd sandbox must run.
case "$(docker image inspect -f '{{.Architecture}}' "$IMAGE")" in
  amd64) want=x64 ;;
  arm64) want=arm64 ;;
  *) echo "unexpected image architecture" >&2; exit 1 ;;
esac
got=$(docker exec "$app" node -p 'process.arch')
[ "$got" = "$want" ] || { echo "node process.arch expected $want, got $got" >&2; exit 1; }
wd=$(docker exec "$app" ./node_modules/.bin/workerd --version)
case "$wd" in
  workerd\ *) echo "$wd" ;;
  *) echo "workerd --version expected 'workerd <version>', got: $wd" >&2; exit 1 ;;
esac

# Persistence: a marker on the volume survives recreating the container.
docker exec "$app" node -e "require('fs').writeFileSync('/app/data/image-test','persistent')"
docker rm -f "$app" >/dev/null
start
wait_ready
marker=$(docker exec "$app" node -p "require('fs').readFileSync('/app/data/image-test','utf8')")
[ "$marker" = persistent ] || { echo "volume marker expected 'persistent', got '$marker'" >&2; exit 1; }
echo "ok: $IMAGE"

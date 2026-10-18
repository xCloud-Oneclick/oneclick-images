#!/usr/bin/env bash
# Check size, user and healthcheck, then run the daemon against a local feed served by a sidecar,
# check the generated HTML, restart, check again. tinyfeed has no HTTP server: the output is a file.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=12

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }

user=$(docker image inspect -f '{{.Config.User}}' "$IMAGE")
[ "$user" = 10001:10001 ] || { echo "expected user 10001:10001, got '$user'" >&2; exit 1; }
[ "$(docker image inspect -f '{{len .Config.Healthcheck.Test}}' "$IMAGE")" != 0 ] \
  || { echo "image has no HEALTHCHECK" >&2; exit 1; }

BUSYBOX='busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e'
tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
net="tf-net-$tag"; srv="tf-feed-$tag"; app="tf-app-$tag"; vol="tf-vol-$tag"

cleanup() {
  docker logs "$app" 2>&1 | tail -n 50 || true
  docker rm -f "$app" "$srv" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
  docker volume rm "$vol" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$net" >/dev/null
docker volume create "$vol" >/dev/null

# Local Atom feed served by busybox httpd (no third-party network access).
docker run -d --name "$srv" --network "$net" --network-alias feedsrv "$BUSYBOX" sh -c '
mkdir -p /www && cat > /www/feed.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>OneClick Test Source</title>
  <id>urn:uuid:11111111-1111-1111-1111-111111111111</id>
  <updated>2026-01-01T00:00:00Z</updated>
  <link href="http://feedsrv/"/>
  <entry>
    <title>Smoke Test Entry</title>
    <id>urn:uuid:22222222-2222-2222-2222-222222222222</id>
    <updated>2026-01-01T00:00:00Z</updated>
    <link href="http://feedsrv/entry"/>
  </entry>
</feed>
EOF
exec httpd -f -p 80 -h /www' >/dev/null
for _ in $(seq 1 30); do
  docker run --rm --network "$net" "$BUSYBOX" wget -q -O- http://feedsrv/feed.xml >/dev/null 2>&1 && break
  sleep 1
done

# First mount of an empty named volume copies /app (owned by the unprivileged user) from the image.
docker run --rm -v "$vol:/app" "$IMAGE" --help >/dev/null 2>&1

# Seed the feeds list into the volume (the image has no shell).
docker run --rm -v "$vol:/app" "$BUSYBOX" sh -c 'echo http://feedsrv/feed.xml > /app/feeds.txt && chown 10001:10001 /app/feeds.txt'

docker run -d --name "$app" --network "$net" -v "$vol:/app" "$IMAGE" \
  --daemon -i feeds.txt -o index.html -n "OneClick Smoke" >/dev/null

check() {
  local label=$1 html=""
  for _ in $(seq 1 30); do
    html=$(docker run --rm -v "$vol:/app:ro" "$BUSYBOX" cat /app/index.html 2>/dev/null || true)
    echo "$html" | grep -q "Smoke Test Entry" && break
    sleep 1
  done
  echo "$html" | grep -q "OneClick Smoke" || { echo "$label: page title missing; first lines:" >&2; echo "$html" | head -n 10 >&2; exit 1; }
  echo "$html" | grep -q "Smoke Test Entry" || { echo "$label: feed entry missing; first lines:" >&2; echo "$html" | head -n 10 >&2; exit 1; }
  [ "$(docker inspect -f '{{.State.Running}}' "$app")" = true ] || { echo "$label: daemon is not running" >&2; exit 1; }
}
check "first run"

# Daemon writes as the unprivileged user.
owner=$(docker run --rm -v "$vol:/app:ro" "$BUSYBOX" stat -c %u /app/index.html)
[ "$owner" = 10001 ] || { echo "index.html owner expected 10001, got $owner" >&2; exit 1; }

docker run --rm -v "$vol:/app" "$BUSYBOX" rm /app/index.html
docker restart "$app" >/dev/null
check "after restart"
echo "ok: $IMAGE"

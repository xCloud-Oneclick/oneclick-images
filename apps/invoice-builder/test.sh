#!/usr/bin/env bash
# Boot the single-container image, check the SPA, the proxied API and database creation, restart, check again.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=245

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }

tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
app="invoice-builder-app-$tag"
cleanup() {
  docker logs "$app" 2>&1 | tail -n 50 || true
  docker exec "$app" sh -c 'tail -n 20 /var/log/nginx/error.log' 2>&1 || true
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

# Prints "<status> <body prefix>" of <method> <path> issued from inside the container against nginx.
req() {
  docker exec "$app" node -e "
    const h=require('http');
    const body='${3:-}';
    const q=h.request({host:'localhost',port:3001,family:4,path:'$2',method:'$1',headers:body?{'content-type':'application/json'}:{}},r=>{
      let s='';r.on('data',c=>s+=c);r.on('end',()=>console.log(r.statusCode,s.slice(0,6000).replace(/\\s+/g,' ')));});
    q.on('error',e=>console.log(0,String(e)));
    q.end(body||undefined);"
}
expect() { # <label> <actual> <expected substring>
  case "$2" in *"$3"*) ;; *) echo "$1: expected '$3', got '$2'" >&2; exit 1;; esac
}

wait_ready() {
  for _ in $(seq 1 60); do
    case "$(req GET /api/health 2>/dev/null || true)" in 200*) return 0;; esac
    sleep 2
  done
  echo "app never became ready; last probe: $(req GET /api/health 2>&1)" >&2
  return 1
}

check() {
  expect "GET /api/health" "$(req GET /api/health)" '200 {"ok":true}'
  expect "GET /api/version" "$(req GET /api/version)" '"version":"3.1.2"'
  expect "GET /" "$(req GET /)" '<title>Invoice Builder</title>'
  # SPA fallback for unknown paths
  expect "GET /some/route" "$(req GET /some/route)" '<title>Invoice Builder</title>'
}

docker run -d --name "$app" "$IMAGE" >/dev/null
wait_ready
check
expect "POST /api/databases" "$(req POST /api/databases '{"fullPath":"smoke.db","mode":"create","dbType":"SQLite","databaseKey":"smoke"}')" '"success":true'
expect "GET /api/databases" "$(req GET /api/databases)" 'smoke.db'
[ "$(docker exec "$app" id -u)" != 0 ] || { echo "container runs as root" >&2; exit 1; }

docker restart "$app" >/dev/null
wait_ready
check
expect "GET /api/databases after restart" "$(req GET /api/databases)" 'smoke.db'
echo "ok: $IMAGE"

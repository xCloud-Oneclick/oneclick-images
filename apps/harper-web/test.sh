#!/usr/bin/env bash
# Boot the image against MariaDB, check /editor and /admin, restart, check again.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=520

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }

MARIADB='mariadb@sha256:2bdff1534a7e569fecaf4b10b66ad0d410806e382d9db29ba305448addda97c4'
tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
net="harper-net-$tag"; db="harper-db-$tag"; app="harper-app-$tag"
pw=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

cleanup() {
  docker logs "$app" 2>&1 | tail -n 40 || true
  docker rm -f "$app" "$db" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Prints the HTTP status of GET <path> issued from inside the app container.
status() {
  docker exec "$app" node -e "fetch('http://localhost:3000$1',{redirect:'manual'}).then(r=>console.log(r.status)).catch(()=>console.log(0))"
}

wait_ready() {
  for _ in $(seq 1 60); do
    [ "$(status /cache-healthcheck 2>/dev/null || echo 0)" = 200 ] && return 0
    sleep 2
  done
  echo "app never became ready" >&2
  return 1
}

if docker run --rm --entrypoint sh "$IMAGE" -c 'command -v npm' >/dev/null 2>&1; then
  echo "npm must not be present in the runtime image" >&2
  exit 1
fi
# Same gate as the publish workflow, so a vulnerable base fails at the pull request.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/aquasecurity/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa \
  image --quiet --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE"

docker run --rm --entrypoint node "$IMAGE" -e "import('mysql2').then(()=>import('drizzle-orm/mysql2')).then(()=>console.log('mysql2 ok'))"

docker network create "$net" >/dev/null
docker run -d --name "$db" --network "$net" \
  -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE=harper \
  -e MARIADB_USER=harper -e "MARIADB_PASSWORD=$pw" "$MARIADB" >/dev/null
for _ in $(seq 1 60); do
  docker exec "$db" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 && break
  sleep 2
done
docker exec "$db" healthcheck.sh --connect --innodb_initialized >/dev/null

docker run -d --name "$app" --network "$net" \
  -e ORIGIN=https://harper.example.test \
  -e "DATABASE_URL=mysql://harper:$pw@$db:3306/harper" "$IMAGE" >/dev/null
wait_ready

[ "$(status /editor)" = 200 ] || { echo "/editor is not 200" >&2; exit 1; }
[ "$(status /admin)" = 404 ] || { echo "/admin is not 404" >&2; exit 1; }
docker exec "$db" mariadb -uharper "-p$pw" harper -N -e 'SHOW TABLES' | grep -q __drizzle_migrations \
  || { echo "migrations were not applied" >&2; exit 1; }

docker restart "$app" >/dev/null
wait_ready
[ "$(status /editor)" = 200 ] || { echo "/editor is not 200 after restart" >&2; exit 1; }
[ "$(status /admin)" = 404 ] || { echo "/admin is not 404 after restart" >&2; exit 1; }
echo "ok: $IMAGE"

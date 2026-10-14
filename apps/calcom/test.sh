#!/usr/bin/env bash
# Check the image size, the unprivileged user and the missing package managers, then boot the image against
# PostgreSQL, check migrations, the app store seed, the version endpoint, the first-run setup page and the
# runtime public URL rewrite, restart, check again.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=2300

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
size_mb=$((size / 1000000))
compressed_mb=$(($(docker save "$IMAGE" | gzip -c | wc -c) / 1000000))
echo "image size: ${size_mb} MB uncompressed, ${compressed_mb} MB compressed (budget ${SIZE_BUDGET_MB} MB uncompressed)"
echo "largest layers:"
docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' "$IMAGE" | sort -hr | head -n 5 | cut -c1-200
[ "$size_mb" -le "$SIZE_BUDGET_MB" ] || { echo "image is larger than the ${SIZE_BUDGET_MB} MB budget" >&2; exit 1; }

[ "$(docker image inspect -f '{{.Config.User}}' "$IMAGE")" = node ] \
  || { echo "image must run as the node user" >&2; exit 1; }
if docker run --rm --entrypoint sh "$IMAGE" -c 'command -v npm || command -v yarn || command -v npx' >/dev/null 2>&1; then
  echo "package managers must not be present in the runtime image" >&2
  exit 1
fi

POSTGRES='postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea'
tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
net="cal-net-$tag"; db="cal-db-$tag"; app="cal-app-$tag"
pw=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
secret=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
enc=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
url=https://cal.example.test

cleanup() {
  docker logs "$app" 2>&1 | tail -n 40 || true
  docker rm -f "$app" "$db" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Prints the HTTP status of GET <path> issued from inside the app container (redirects are not followed).
status() {
  docker exec "$app" node -e "fetch('http://localhost:3000$1',{redirect:'manual'}).then(r=>console.log(r.status)).catch(()=>console.log(0))"
}

# Prints 1 when the body of GET <path> contains <needle>, else 0.
body_has() {
  docker exec "$app" node -e "fetch('http://localhost:3000$1').then(r=>r.text()).then(t=>console.log(t.includes('$2')?1:0)).catch(()=>console.log(0))"
}

wait_ready() {
  for _ in $(seq 1 150); do
    [ "$(status /api/version 2>/dev/null || echo 0)" = 200 ] && return 0
    sleep 4
  done
  echo "app never became ready" >&2
  return 1
}

check() {
  local code
  code=$(status '/auth/setup?step=1')
  [ "$code" = 200 ] || { echo "/auth/setup?step=1 returned $code $1" >&2; exit 1; }
  [ "$(body_has '/auth/setup?step=1' cal.example.test)" = 1 ] || { echo "public URL was not applied $1" >&2; exit 1; }
  [ "$(body_has '/auth/setup?step=1' NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER)" = 0 ] || { echo "build placeholder left in pages $1" >&2; exit 1; }
}

docker network create "$net" >/dev/null
docker run -d --name "$db" --network "$net" \
  -e POSTGRES_DB=calendso -e POSTGRES_USER=cal -e "POSTGRES_PASSWORD=$pw" "$POSTGRES" >/dev/null
for _ in $(seq 1 60); do
  docker exec "$db" pg_isready -h localhost -U cal -d calendso >/dev/null 2>&1 && break
  sleep 2
done
docker exec "$db" pg_isready -h localhost -U cal -d calendso >/dev/null

docker run -d --name "$app" --network "$net" \
  -e "DATABASE_URL=postgresql://cal:$pw@$db:5432/calendso" \
  -e "DATABASE_DIRECT_URL=postgresql://cal:$pw@$db:5432/calendso" \
  -e "NEXT_PUBLIC_WEBAPP_URL=$url" -e "NEXTAUTH_URL=$url/api/auth" \
  -e "NEXTAUTH_SECRET=$secret" -e "CALENDSO_ENCRYPTION_KEY=$enc" \
  -e CALCOM_TELEMETRY_DISABLED=1 "$IMAGE" >/dev/null
wait_ready
[ "$(docker exec "$app" id -u)" != 0 ] || { echo "app runs as root" >&2; exit 1; }
check "after first start"
docker exec "$db" psql -U cal -d calendso -tAc 'SELECT count(*) FROM _prisma_migrations' | grep -qE '^[1-9][0-9]*$' \
  || { echo "migrations were not applied" >&2; exit 1; }
docker exec "$db" psql -U cal -d calendso -tAc 'SELECT count(*) FROM "App"' | grep -qE '^[1-9][0-9]*$' \
  || { echo "app store was not seeded" >&2; exit 1; }

docker restart "$app" >/dev/null
wait_ready
check "after restart"
echo "ok: $IMAGE"

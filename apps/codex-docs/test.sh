#!/usr/bin/env bash
# Boot the image, check / and the login flow (wrong and right password), restart, check again.
set -euo pipefail
: "${IMAGE:?IMAGE is required}"

SIZE_BUDGET_MB=200

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
[ "$(docker run --rm --entrypoint id "$IMAGE" -u)" != 0 ] || { echo "image runs as root" >&2; exit 1; }
# Same gate as the publish workflow, so a vulnerable base fails at the pull request.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/aquasecurity/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa \
  image --quiet --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE"

tag=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')
app="codexdocs-app-$tag"
pw=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
jar=$(mktemp)

cleanup() {
  docker logs "$app" 2>&1 | tail -n 50 || true
  docker rm -f "$app" >/dev/null 2>&1 || true
  rm -f "$jar"
}
trap cleanup EXIT

docker run -d --name "$app" -p 3000 \
  -e "APP_CONFIG_auth_password=\"$pw\"" -e 'APP_CONFIG_auth_secret="smoke-test-secret"' "$IMAGE" >/dev/null
base="http://localhost:$(docker port "$app" 3000/tcp | head -n1 | sed 's/.*://')"

wait_ready() {
  for _ in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$base/" || true)" = 200 ] && return 0
    sleep 2
  done
  echo "app never became ready" >&2
  return 1
}

check() {
  local code body csrf
  code=$(curl -s -o /dev/null -w '%{http_code}' "$base/")
  [ "$code" = 200 ] || { echo "GET / expected 200, got $code" >&2; exit 1; }

  : >"$jar"
  body=$(curl -s -c "$jar" -b "$jar" "$base/auth")
  echo "$body" | grep -q 'Enter a password to access pages editing' \
    || { echo "/auth: login form marker missing; body starts:" >&2; echo "$body" | head -n 5 >&2; exit 1; }
  csrf=$(echo "$body" | sed -n 's/.*name="_csrf" value=\([^ >]*\).*/\1/p' | head -n1 | tr -d '"')
  [ -n "$csrf" ] || { echo "no csrf token in /auth" >&2; exit 1; }

  body=$(curl -s -c "$jar" -b "$jar" --data-urlencode "_csrf=$csrf" --data-urlencode "password=wrong" "$base/auth")
  echo "$body" | grep -q 'Wrong password' || { echo "wrong password was not rejected" >&2; exit 1; }

  code=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -c "$jar" -b "$jar" \
    --data-urlencode "_csrf=$csrf" --data-urlencode "password=$pw" "$base/auth")
  case "$code" in
    "302 "*) ;;
    *) echo "login expected 302 redirect, got: $code" >&2; exit 1 ;;
  esac
  grep -q authToken "$jar" || { echo "no authToken cookie after login" >&2; exit 1; }
}

wait_ready
check
docker restart "$app" >/dev/null
wait_ready
check
echo "ok: $IMAGE"

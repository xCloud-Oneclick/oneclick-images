#!/usr/bin/env bash
# Prints a JSON array of app slugs whose apps/<slug>/ changed between BASE and HEAD.
# APP=<slug> forces a single app (workflow_dispatch).
set -euo pipefail

if [ -n "${APP:-}" ]; then
  [[ "$APP" =~ ^[a-z0-9-]+$ ]] || { echo "invalid app slug" >&2; exit 1; }
  [ -f "apps/$APP/build.yaml" ] || { echo "apps/$APP/build.yaml not found" >&2; exit 1; }
  printf '["%s"]\n' "$APP"
  exit 0
fi

git diff --name-only "$BASE" "$HEAD" -- apps/ \
  | awk -F/ 'NF>2 {print $2}' | sort -u \
  | while read -r slug; do [[ "$slug" =~ ^[a-z0-9-]+$ ]] && [ -f "apps/$slug/build.yaml" ] && echo "$slug"; done \
  | jq -Rsc 'split("\n") | map(select(length > 0))'

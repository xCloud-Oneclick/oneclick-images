#!/usr/bin/env bash
# Validates apps/<slug>/build.yaml and appends image=, version=, dockerfile= to $GITHUB_OUTPUT.
set -euo pipefail
slug=$1
cfg="apps/$slug/build.yaml"

image=$(yq -r .image "$cfg")
version=$(yq -r .version "$cfg")
dockerfile=$(yq -r '.dockerfile // "Dockerfile"' "$cfg")

[[ "$image" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "invalid image name: $image" >&2; exit 1; }
[[ "$version" =~ ^[0-9A-Za-z._-]+-xcloud\.[0-9]+$ ]] || { echo "version must end in -xcloud.<n>: $version" >&2; exit 1; }
[[ "$dockerfile" =~ ^[A-Za-z0-9._/-]+$ && "$dockerfile" != *..* ]] || { echo "invalid dockerfile path" >&2; exit 1; }
[ -f "apps/$slug/$dockerfile" ] || { echo "apps/$slug/$dockerfile not found" >&2; exit 1; }
[ -x "apps/$slug/test.sh" ] || { echo "apps/$slug/test.sh missing or not executable" >&2; exit 1; }

{
  echo "image=$image"
  echo "version=$version"
  echo "dockerfile=apps/$slug/$dockerfile"
} >>"$GITHUB_OUTPUT"

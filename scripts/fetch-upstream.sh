#!/usr/bin/env bash
# Checks out apps/<slug>'s upstream release into ./src and verifies the tag points at the pinned commit.
set -euo pipefail
slug=$1
cfg="apps/$slug/build.yaml"

upstream=$(yq -r .upstream "$cfg")
ref=$(yq -r .ref "$cfg")
commit=$(yq -r .commit "$cfg")
[[ "$upstream" == https://github.com/* ]] || { echo "upstream must be a https://github.com/ URL" >&2; exit 1; }
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "commit must be a full 40-char SHA" >&2; exit 1; }

git init -q src
git -C src fetch -q --depth 1 "$upstream" "refs/tags/$ref"
actual=$(git -C src rev-parse 'FETCH_HEAD^{commit}')
[ "$actual" = "$commit" ] || { echo "$ref resolves to $actual, build.yaml pins $commit" >&2; exit 1; }
git -C src checkout -q "$commit"

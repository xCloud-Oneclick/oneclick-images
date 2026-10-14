#!/usr/bin/env bash
# Fails if tracked files contain private keys, IPv4 literals, or any pattern in $DENYLIST
# (newline-separated extended regexes, kept outside the repo).
set -euo pipefail
status=0

check() {
  local label=$1 pattern=$2
  if git grep -nIE -e "$pattern" -- . ':!scripts/leak-check.sh' >/tmp/hits 2>/dev/null; then
    echo "::error::$label"; cat /tmp/hits; status=1
  fi
}

check "private key material" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
check "IPv4 address literal" '\b(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])){3}\b'

if [ -n "${DENYLIST:-}" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && check "denylisted internal reference" "$p"
  done <<<"$DENYLIST"
fi

exit $status

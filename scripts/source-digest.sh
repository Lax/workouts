#!/usr/bin/env bash
set -uo pipefail

source="$1"
before="${2:-}"

digest=$(find "data/raw/$source" "data/std/$source" -type f \
  -exec md5sum {} + 2>/dev/null | sort -k2 | md5sum | cut -d' ' -f1 || true)
[ -z "$digest" ] && digest="none"

if [ -n "$before" ]; then
  [ "$before" != "$digest" ] && echo "changed=true" || echo "changed=false"
else
  echo "$digest"
fi

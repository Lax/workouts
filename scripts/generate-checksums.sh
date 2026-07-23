#!/usr/bin/env bash
set -euo pipefail

for target in "$@"; do
  target="${target%/}"
  if [ -f "$target" ]; then
    sha256sum "$target" > "${target}.SHA256SUMS"
  elif [ -d "$target" ]; then
    (cd "$target" && find . -type f ! -name 'SHA256SUMS' -print0 2>/dev/null \
      | sort -z | xargs -0 sha256sum 2>/dev/null \
      | sed 's| \./| |') > "${target}/SHA256SUMS" || true
  fi
done

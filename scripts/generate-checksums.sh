#!/usr/bin/env bash
set -euo pipefail

for target in "$@"; do
  target="${target%/}"
  if [ -f "$target" ]; then
    sha256sum "$target" > "${target}.SHA256SUMS"
  elif [ -d "$target" ]; then
    pushd "$target" >/dev/null
    find . -type f ! -name 'SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS 2>/dev/null || true
    popd >/dev/null
  fi
done

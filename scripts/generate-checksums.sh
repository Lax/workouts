#!/usr/bin/env bash
set -euo pipefail

for target in "$@"; do
  target="${target%/}"
  ckfile="${target}.checksum"
  if [ -f "$target" ]; then
    sha256sum "$target" > "$ckfile"
  elif [ -d "$target" ]; then
    find "$target" -type f ! -name '*.checksum' -print0 2>/dev/null \
      | sort -z | xargs -0 sha256sum > "$ckfile" 2>/dev/null || true
  fi
done

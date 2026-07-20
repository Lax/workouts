#!/usr/bin/env bash
set -uo pipefail

source="$1"
ck="data/raw/$source/.checksum"
[ -f "$ck" ] && awk '{print $1}' "$ck" | sha256sum | cut -d' ' -f1 || echo "none"

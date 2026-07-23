#!/usr/bin/env bash
set -uo pipefail

# DEPRECATED: replaced by generate-checksums.sh + per-source SHA256SUMS
# Retained for backward compat — reads SHA256SUMS (preferred) or .checksum (legacy)

source="$1"
ck="data/raw/$source/SHA256SUMS"
[ -f "$ck" ] && sha256sum "$ck" | cut -d' ' -f1 && exit 0
ck="data/raw/$source/.checksum"
[ -f "$ck" ] && awk '{print $1}' "$ck" | sha256sum | cut -d' ' -f1 || echo "none"

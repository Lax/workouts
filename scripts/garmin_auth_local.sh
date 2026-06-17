#!/usr/bin/env bash
# Garmin DI OAuth2 — local auth + cache sync
#
# Default: reads email + password from config.yml, runs garmin_auth.py
# with strategic MFA code over stdin, Base64-encodes the DI OAuth2
# token, updates config.yml, and sets the GitHub Secret.
#
# --sync: skips SSO, reads the latest cache token from
# data/cache/garmin_garmin_com_tokens.json, Base64-encodes it,
# updates config.yml + GitHub Secret.
#
# Usage:
#   ./scripts/garmin_auth_local.sh          # full SSO + MFA auth
#   ./scripts/garmin_auth_local.sh --sync   # push cache token to seed
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/config.yml"
SCRIPT="$ROOT/scripts/garmin_auth.py"
CACHE="$ROOT/data/cache/garmin_garmin_com_tokens.json"
REPO="Lax/workouts"
SECRET="SYNC_GARMIN_AUTH_SEED"
SYNC_MODE=false

case "${1:-}" in
  --sync) SYNC_MODE=true ;;
  "") ;;
  *) echo "Usage: $0 [--sync]" >&2; exit 1 ;;
esac

if [ ! -f "$CONFIG" ]; then
  echo "config/config.yml not found — run: bundle exec exe/workouts init" >&2
  exit 1
fi

# --- Obtain TOKEN_JSON ---
if [ "$SYNC_MODE" = true ]; then
  if [ ! -f "$CACHE" ]; then
    echo "Cache file not found: $CACHE" >&2
    echo "Run without --sync first to perform SSO auth." >&2
    exit 1
  fi
  echo "[--sync] Using cache token (no SSO)" >&2
  TOKEN_JSON=$(cat "$CACHE")
else
  eval "$(ruby -ryaml -e "
    c = (YAML.safe_load(File.read('$CONFIG')) || {}).dig('sync','garmin') || {}
    puts \"EMAIL=#{c['email']}\"
    puts \"PWD=#{c['password']}\"
  ")"

  if [ -z "${EMAIL:-}" ] || [ -z "${PWD:-}" ]; then
    echo "sync.garmin.email / sync.garmin.password not set in config.yml" >&2
    exit 1
  fi

  echo "" >&2
  echo "=== Garmin DI OAuth2 Auth ===" >&2
  echo "" >&2
  TOKEN_JSON=$(
    SYNC__GARMIN__EMAIL="$EMAIL" \
    SYNC__GARMIN__PASSWORD="$PWD" \
    python3 "$SCRIPT"
  )

  # After SSO, the cache was just written by Ruby _di_exchange in the script.
  # If auth succeeded but the script didn't write to cache (older scripts),
  # Ruby load_auth_seed → save_tokens will create it on next sync run.
fi

# --- Base64 encode ---
B64=$(echo "$TOKEN_JSON" | python3 -c "
import sys, json, base64
data = json.load(sys.stdin)
print(base64.b64encode(json.dumps(data).encode()).decode())
")

# --- Update config.yml ---
ruby -ryaml -e "
  path = '$CONFIG'
  cfg = YAML.safe_load(File.read(path)) || {}
  cfg['sync'] ||= {}
  cfg['sync']['garmin'] ||= {}
  cfg['sync']['garmin']['auth_seed'] = '$B64'
  File.write(path, YAML.dump(cfg))
  puts 'sync.garmin.auth_seed updated in config.yml'
"

# --- GitHub Secret ---
print_secret_help() {
  echo "" >&2
  echo "===========================================" >&2
  echo "  GitHub Actions Secret (one-time setup)" >&2
  echo "  Name:   $SECRET" >&2
  echo "===========================================" >&2
  echo "" >&2
  echo "Set manually at:" >&2
  echo "  https://github.com/Lax/workouts/settings/secrets/actions" >&2
  echo "" >&2
  echo "Name:  $SECRET" >&2
  echo "Value: $B64" >&2
  echo "" >&2
}

skipped=false

if ! command -v gh &>/dev/null; then
  echo "" >&2
  echo "⚠️  gh CLI not found — run: brew install gh (or visit the URL below)" >&2
  print_secret_help
  skipped=true
fi

if ! $skipped && ! gh auth status &>/dev/null 2>&1; then
  echo "" >&2
  echo "⚠️  gh CLI not authenticated — run: gh auth login" >&2
  print_secret_help
  skipped=true
fi

if ! $skipped && ! gh repo view "$REPO" &>/dev/null 2>&1; then
  echo "" >&2
  echo "⚠️  No access to $REPO — token only written to config.yml" >&2
  print_secret_help
  skipped=true
fi

if ! $skipped && ! gh secret list -R "$REPO" &>/dev/null 2>&1; then
  echo "" >&2
  echo "⚠️  No permission to write GitHub Secrets on $REPO" >&2
  print_secret_help
  skipped=true
fi

if ! $skipped; then
  if echo "$B64" | gh secret set "$SECRET" -R "$REPO" 2>/dev/null; then
    echo "" >&2
    echo "✅  GitHub Secret set: $SECRET" >&2
  else
    echo "" >&2
    echo "❌  Failed to set GitHub Secret (unexpected error)" >&2
    print_secret_help
  fi
fi

echo "Done. Token cached in config.yml. CI will auto-refresh via di_refresh (30d sliding)." >&2

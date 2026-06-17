#!/usr/bin/env bash
# Garmin DI OAuth2 — local interactive auth (one-time setup)
#
# Reads email + password from config.yml, runs garmin_auth.py
# with strategic MFA code over stdin, Base64-encodes the DI OAuth2
# token, updates config.yml, and prints the GitHub Secret command.
#
# Usage: ./scripts/garmin_auth_local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/config.yml"
SCRIPT="$ROOT/scripts/garmin_auth.py"

if [ ! -f "$CONFIG" ]; then
  echo "config/config.yml not found — run: bundle exec exe/workouts init" >&2
  exit 1
fi

# --- 1. Read credentials from config.yml ---
eval "$(ruby -ryaml -e "
  c = (YAML.safe_load(File.read('$CONFIG')) || {}).dig('sync','garmin') || {}
  puts \"EMAIL=#{c['email']}\"
  puts \"PWD=#{c['password']}\"
")"

if [ -z "${EMAIL:-}" ] || [ -z "${PWD:-}" ]; then
  echo "sync.garmin.email / sync.garmin.password not set in config.yml" >&2
  exit 1
fi

# --- 2. Run auth (stderr → progress + MFA prompt; stdout → JSON token) ---
echo "" >&2
echo "=== Garmin DI OAuth2 Auth ===" >&2
echo "" >&2
TOKEN_JSON=$(
  SYNC__GARMIN__EMAIL="$EMAIL" \
  SYNC__GARMIN__PASSWORD="$PWD" \
  python3 "$SCRIPT"
)

# --- 3. Base64 encode ---
B64=$(echo "$TOKEN_JSON" | python3 -c "
import sys, json, base64
data = json.load(sys.stdin)
print(base64.b64encode(json.dumps(data).encode()).decode())
")

# --- 4. Update config.yml ---
ruby -ryaml -e "
  path = '$CONFIG'
  cfg = YAML.safe_load(File.read(path)) || {}
  cfg['sync'] ||= {}
  cfg['sync']['garmin'] ||= {}
  cfg['sync']['garmin']['refresh_token'] = '$B64'
  File.write(path, YAML.dump(cfg))
  puts 'sync.garmin.refresh_token updated in config.yml'
"

# --- 5. Print GitHub Secret instructions ---
echo "" >&2
echo "===========================================" >&2
echo "  GitHub Actions Secret (one-time setup)" >&2
echo "  Name:   SYNC_GARMIN_REFRESH_TOKEN" >&2
echo "===========================================" >&2
echo "" >&2

if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  echo "$B64" | gh secret set SYNC_GARMIN_REFRESH_TOKEN
  echo "GitHub Secret set via gh CLI." >&2
else
  echo "Set manually at:" >&2
  echo "  https://github.com/Lax/workouts/settings/secrets/actions" >&2
  echo "" >&2
  echo "Name:  SYNC_GARMIN_REFRESH_TOKEN" >&2
  echo "Value: $B64" >&2
fi

echo "" >&2
echo "Done. Token cached in config.yml. CI will auto-refresh via di_refresh (30d sliding)." >&2

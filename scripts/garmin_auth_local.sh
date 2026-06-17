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
  cfg['sync']['garmin']['auth_seed'] = '$B64'
  File.write(path, YAML.dump(cfg))
  puts 'sync.garmin.auth_seed updated in config.yml'
"

# --- 5. Set GitHub Secret (multi-level permission check) ---

print_secret_help() {
  echo "" >&2
  echo "===========================================" >&2
  echo "  GitHub Actions Secret (one-time setup)" >&2
  echo "  Name:   SYNC_GARMIN_AUTH_SEED" >&2
  echo "===========================================" >&2
  echo "" >&2
  echo "Set manually at:" >&2
  echo "  https://github.com/Lax/workouts/settings/secrets/actions" >&2
  echo "" >&2
  echo "Name:  SYNC_GARMIN_AUTH_SEED" >&2
  echo "Value: $B64" >&2
  echo "" >&2
}

REPO="Lax/workouts"
SECRET="SYNC_GARMIN_AUTH_SEED"
skipped=false

# Level 0: gh CLI installed
if ! command -v gh &>/dev/null; then
  echo "" >&2
  echo "⚠️  gh CLI not found — run: brew install gh (or visit the URL below)" >&2
  print_secret_help
  skipped=true
fi

# Level 1: gh CLI authenticated
if ! $skipped && ! gh auth status &>/dev/null 2>&1; then
  echo "" >&2
  echo "⚠️  gh CLI not authenticated — run: gh auth login" >&2
  print_secret_help
  skipped=true
fi

# Level 2: repo access
if ! $skipped && ! gh repo view "$REPO" &>/dev/null 2>&1; then
  echo "" >&2
  echo "⚠️  No access to $REPO — token only written to config.yml" >&2
  print_secret_help
  skipped=true
fi

# Level 3: secret write permission
if ! $skipped && ! gh secret list -R "$REPO" &>/dev/null 2>&1; then
  echo "" >&2
  echo "⚠️  No permission to write GitHub Secrets on $REPO" >&2
  print_secret_help
  skipped=true
fi

# Level 4: all checks passed — set secret
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

# Strava Web Auth — JWT Cookie

`workouts strava fetch` downloads original activity files from the Strava website.
This requires a `strava_remember_token` JWT cookie from a browser session.

## Obtain the JWT

### Chrome / Edge

1.  Open `https://www.strava.com/login` and log in with email + OTP
2.  Press **F12** → **Application** tab
3.  Left sidebar: **Storage** → **Cookies** → `https://www.strava.com`
4.  Find `strava_remember_token` and copy its **Value**

### Firefox

1.  Open `https://www.strava.com/login` and log in
2.  Press **F12** → **Storage** tab
3.  Left: **Cookies** → `https://www.strava.com`
4.  Copy the **Value** of `strava_remember_token`

### Safari

1.  Open `https://www.strava.com/login` and log in
2.  **Develop** menu → **Show Web Inspector** → **Storage** tab
3.  **Cookies** → `www.strava.com` → `strava_remember_token` → copy **Value**

## JWT lifetime

The JWT `exp` claim typically grants **~30 days**. The cookie `Max-Age` is 365 days
but the server enforces the JWT expiry. Re-login is needed monthly.

## Configuration

### Local (config.yml)

```yaml
sync:
  strava:
    web_auth:
      jwt: "eyJ..."        # paste the JWT value here
```

### Environment variable

```bash
export SYNC__STRAVA__WEB_AUTH__JWT="eyJ..."
```

### GitHub Secret (CI)

GitHub Secret name: `SYNC_STRAVA_WEB_AUTH_SEED`

The value is the Base64-encoded JWT:

```bash
echo -n "eyJ..." | base64 -w0
gh secret set SYNC_STRAVA_WEB_AUTH_SEED -R Lax/workouts --body "$(echo -n 'eyJ...' | base64 -w0)"
```

The `auth_seed` field in config.yml serves the same purpose:

```yaml
sync:
  strava:
    web_auth:
      auth_seed: "<base64-encoded-jwt>"
```

## Session caching

After first use, the session is persisted to `data/cache/strava_session.yml`.
Subsequent runs reuse the cached session, avoiding a re-verification round-trip.
The file is tracked by GitHub Actions `tokens-cache` for CI reuse.

## CLI priority

| Priority | Source |
|----------|--------|
| 1 | `--jwt` CLI option |
| 2 | `SYNC__STRAVA__WEB_AUTH__JWT` env var |
| 3 | `config.yml` → `sync.strava.web_auth.jwt` |
| 4 | `SYNC__STRAVA__WEB_AUTH__AUTH_SEED` env var |
| 5 | `config.yml` → `sync.strava.web_auth.auth_seed` |
| 6 | `data/cache/strava_session.yml` (cached session) |

# Garmin OAuth Auth — Design

Garmin Connect API uses two auth paths depending on domain:

- **garmin.com** (international): DI OAuth2 (since CF block, Mar 2026)
- **garmin_cn** (China): Original OAuth1→OAuth2 chain (unaffected by CF)

## garmin.com: DI OAuth2 Flow

| Token | Source | TTL | Use |
|---|---|---|---|
| DI OAuth2 access_token | SSO → CAS → DI exchange | ~18h | Authorization: Bearer |
| DI OAuth2 refresh_token | same exchange | ~30d sliding | renew access_token |

### Auth priority chain (Garmin#authenticate → authenticate_di)

```
① DI token cache (data/cache/garmin_garmin_com_tokens.json, GH Cache)
   DI access_token valid? → use directly.
   expired? → di_refresh (POST diauth.garmin.com) → new token → save cache.
   refresh fail? → remove stale cache.

② Strategy A: curl_cffi subprocess (scripts/garmin_auth.py)
   portal+cffi: /portal/api/login (5 TLS fingerprints, 30-45s delay)
   mobile+cffi: /mobile/api/login (Safari TLS, fallback)
   → CAS ticket → DI OAuth2 exchange → save cache.

③ Strategy B: Playwright subprocess (scripts/garmin_auth_playwright.py)
   Headless Chromium → widget/portal form login → ticket → DI exchange
   Session cookies cached (~1 year) to avoid repeat MFA.
   Fallback only — heavier deps (~500MB Chromium).

④ Failure → false (no SSO in CI)
```

### CI cache design

| Cache | Key | Path |
|---|---|---|
| DI token | `garmin-tokens-v1-garmin-{run_id}` | `data/cache/garmin_garmin_com_tokens.json` |
| Playwright browser (optional) | `garmin-playwright-browser-v1-{os}` | `~/.cache/ms-playwright` |

Email + password live in GitHub Secrets (`SYNC_GARMIN_EMAIL`, `SYNC_GARMIN_PASSWORD`).
Token lives only in GH Cache (not in repo, not in GitHub Secrets).

### Subprocess interface

Both `garmin_auth.py` and `garmin_auth_playwright.py`:
- Input: `GARMIN_EMAIL`, `GARMIN_PASSWORD`, `GARMIN_DOMAIN` env vars
- Output: JSON DI OAuth2 token to stdout, exit 0 on success
- MFA: `GARMIN_MFA_CODE` env var (optional)

## garmin_cn: OAuth1→OAuth2 Chain (unchanged)

```
① secret (config.yml / env SYNC__{SOURCE}__SECRET)
   Base64([OAuth1 JSON, OAuth2 JSON]) — garth dumps() compatible.
   Parse → OAuth2 valid? → use directly.
   OAuth2 expired? → OAuth1 refresh → new OAuth2.
   Fail → degrade.

② token file (~/.workouts/garmin_tokens.json)
   Same logic. Fail → delete stale.

③ SSO login (email+password, interactive, MFA supported)
   On success: dump_secret → verify_access_token.
   Verify pass → save_secret_to_config + save_tokens.
```

### Credentials

| Credential | Source | TTL | Use |
|---|---|---|---|
| OAuth1 token+secret | GET /preauthorized (SSO) | months~years | sign OAuth2 exchange |
| OAuth2 access_token | OAuth1 signed POST /exchange/user/2.0 | ~6h | Authorization: Bearer |
| OAuth2 refresh_token | same as access_token | ~90d | new access_token |

## Architecture

```
GarminBase#authenticate
  ├── @domain == "garmin.com"? → authenticate_di (DI OAuth2)
  └── else                    → authenticate_oauth1 (original OAuth1 chain)
```

`Garmin` (< 20 lines) sets `@domain = "garmin.com"`, inherit all DI logic.
`GarminCN` (< 20 lines) sets `@domain = "garmin.cn"`, inherit all OAuth1 logic.

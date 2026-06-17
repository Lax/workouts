# Garmin OAuth Auth — Design

Garmin Connect API 用两层 OAuth: OAuth1（长期凭证）+ OAuth2（短期令牌）。

## Credentials

| Credential | Source | TTL | Use |
|---|---|---|---|
| OAuth1 token+secret | GET /preauthorized (SSO) | months~years | sign OAuth2 exchange |
| OAuth2 access_token | OAuth1 signed POST /exchange/user/2.0 | ~6h | Authorization: Bearer |
| OAuth2 refresh_token | same as access_token | ~90d | new access_token |

## Auth priority chain (GarminBase#authenticate)

```
① secret (config.yml / env SYNC__{SOURCE}__SECRET)
   Base64([OAuth1 JSON, OAuth2 JSON]) — garth dumps() compatible.
   Parse -> OAuth2 valid? -> use directly.
   OAuth2 expired? -> OAuth1 refresh -> new OAuth2.
   Fail (parse / OAuth1 expired) -> degrade.

② token file (~/.workouts/garmin_tokens.json)
   Same logic as ①.
   Fail -> delete stale file -> degrade.

③ SSO login (email+password, interactive, MFA supported)
   On success: dump_secret -> verify_access_token (API probe).
   Verify pass -> save_secret_to_config (back to config.yml) + save_tokens.
   Verify fail -> discard, raise AuthError (no infinite loop).
```

## Why secret first

OAuth1 is long-lived. Generate once via garth or `auth garmin_cn`.
CI environment uses only secret (env var, no interactive SSO).
OAuth2 auto-refresh every ~6h. OAuth1 stays same -> no secret rewrite.

Secrets `SYNC__GARMIN_CN__SECRET` and `SYNC__GARMIN__SECRET` are GitHub repo secrets.
`SYNC__{SOURCE}__EMAIL` / `SYNC__{SOURCE}__PASSWORD` exist as fallback only.

## CI failure modes

| Condition | Behavior |
|---|---|
| secret exists | parse + use, OAuth2 expired -> auto refresh |
| OAuth2 refresh ok | continue sync |
| OAuth1 expired (rare) | no SSO (interactive unavailable), sync returns 0 |
| Fix | local `auth garmin_cn` -> new secret -> update GitHub Secret |

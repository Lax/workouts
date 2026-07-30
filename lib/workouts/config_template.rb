module Workouts
  class ConfigTemplate
    def self.generate
      <<~YAML
        ---
        database:
          path: data/workouts.db

        sync:
          # time_budget: 300            # Max seconds per sync run (optional, env: SYNC__TIME_BUDGET)

          # strava:
          #   client_id: ""
          #   client_secret: ""
          #   refresh_token: ""
          #   web_auth:
          #     jwt: "eyJ..."              # strava_remember_token from browser DevTools
          #     # auth_seed: "<base64>"    # Base64(jwt) for GitHub Secret SYNC_STRAVA_WEB_AUTH_SEED
          #   # Docs: docs/strava-web-auth.md

          # --- Garmin International (garmin.com) ---
          # DI OAuth2 flow. Run ./scripts/garmin_auth_local.sh for MFA login.
          # CI uses auth_seed only — email/password not needed or recommended.
          # garmin:
          #   auth_seed: "base64_di_token"    # auto-written by auth_local.sh
          #   email: "your@email.com"         # ⚠️ only for local script (garmin_auth.py)
          #   password: "your_password"       # ⚠️ only for local script (garmin_auth.py)

          # --- Garmin China (garmin.cn) ---
          # Uses OAuth1 token chain (unaffected by garmin.com CF block).
          # Use either email+password OR secret (garth token string).
          # Generate token from reachable network via:
          #   python3 -c "import garth; garth.configure(domain='garmin.cn', ssl_verify=False); garth.login('email','password'); print(garth.client.dumps())"
          # garmin_cn:
          #   email: "13800138000"             # placeholder
          #   password: "your_password"        # placeholder
          #   # secret: "base64_garth_token"   # alternative to email+password

          # keep:
          #   phone: "13800138000"      # placeholder
          #   password: "your_password"  # placeholder
          #   # or via env: SYNC__KEEP__PHONE / SYNC__KEEP__PASSWORD
          #   # Keep data uses GCJ-02 coordinates (auto-converted to WGS84)

          # igpsport:
          #   phone: "13800138000"      # placeholder
          #   password: "your_password"  # placeholder

          # xoss:                        # XOSS international (backend.xoss.co)
          #   email: "your@email.com"    # placeholder — FIT download + GPS
          #   password: "your_password"  # placeholder

          # xingzhe:                     # 行者国内版 (imxingzhe.com)
          #   email: "13800138000"       # placeholder
          #   password: "your_password"  # placeholder

        export:
          json:
            path: site/activities.json
          svg:
            dir: site/svg
          csv:
            path: site/workouts.csv

        privacy:
          start_end_range: 200

        system:
          units: metric
          log_level: info
          timezone: Asia/Shanghai
      YAML
    end
  end
end

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

          # --- Garmin International (garmin.com) ---
          # Use either email+password OR secret (garth token string).
          # SSO login is currently blocked by Cloudflare 429 globally.
          # Workaround: generate token from reachable network via:
          #   python3 -c "import garth; garth.login('email','pw'); print(garth.client.dumps())"
          # garmin:
          #   email: "your@email.com"          # placeholder
          #   password: "your_password"        # placeholder
          #   # secret: "base64_garth_token"   # alternative to email+password

          # --- Garmin China (garmin.cn) ---
          # garmin_cn:
          #   email: "13800138000"             # placeholder
          #   password: "your_password"        # placeholder

          # keep:
          #   phone: "13800138000"      # placeholder
          #   password: "your_password"  # placeholder
          #   # or via env: SYNC__KEEP__PHONE / SYNC__KEEP__PASSWORD
          #   # Keep data uses GCJ-02 coordinates (auto-converted to WGS84)

          # igpsport:
          #   phone: "13800138000"      # placeholder
          #   password: "your_password"  # placeholder

          # xoss:                        # XOSS international (xoss.co)
          #   email: "your@email.com"    # placeholder
          #   password: "your_password"  # placeholder

          # xingzhe:                     # 行者国内版 (imxingzhe.com)
          #   email: "13800138000"       # placeholder
          #   password: "your_password"  # placeholder

        export:
          json:
            path: build/activities.json
          svg:
            dir: build/svg
          csv:
            path: build/workouts.csv

        privacy:
          start_end_range: 200

        system:
          units: metric
          log_level: info
          timezone: UTC
      YAML
    end
  end
end

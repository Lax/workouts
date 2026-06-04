module Workouts
  class ConfigTemplate
    def self.generate
      <<~YAML
        ---
        database:
          path: data/workouts.db

        sync:
          # strava:
          #   client_id: ""
          #   client_secret: ""
          #   refresh_token: ""

          # garmin:
          #   email: ""
          #   password: ""

          # garmin_cn:
          #   email: ""
          #   password: ""

          # keep:
          #   phone: ""        # or env: SYNC__KEEP__PHONE
          #   password: ""     # or env: SYNC__KEEP__PASSWORD
          #   # Keep data uses GCJ-02 coordinates (auto-converted to WGS84)

          # igpsport:
          #   phone: ""
          #   password: ""

          # xoss:
          #   email: ""            # XOSS international (xoss.co)
          #   password: ""

          # xingzhe:
          #   email: ""            # 行者国内版 (imxingzhe.com)
          #   password: ""

        export:
          json:
            path: data/activities.json
          svg:
            dir: data/svg
          csv:
            path: data/workouts.csv

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

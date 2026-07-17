module Workouts
  module Cli
    module Sync
      def sync
        db = connect_db
        sources = if options[:source]
                    [options[:source]]
                  else
                    %w[igpsport keep xoss xingzhe garmin_cn garmin strava].select do |s|
                      source_configured?(s)
                    end
                  end

        filter = options[:activity]&.map(&:strip)&.map(&:downcase)

        if sources.size == 1
          source = sources.first
          say_status :syncing, source, :green
          adapter = build_sync_adapter(source, db, filter)
          if adapter
            begin
              count = adapter.call
              if count == 0
                say_status :warn, "#{source}: 0 activities", :yellow
              else
                say_status :done, "#{source}: #{count} activities", :green
              end
            rescue => e
              say_status :error, "#{source}: #{e.message}", :red
            end
          end
        else
          runner = Workouts::Sync::Runner.new(
            sources: sources, db: db, config: workouts_config,
            activity_filter: filter,
            num_workers: (workouts_config.dig("sync", "workers") || 3).to_i,
            time_budget: workouts_config.dig("sync", "time_budget")
          )
          runner.run
        end
      end

      # auth garmin: redirect to scripts/garmin_auth_local.sh (MFA-only, DI OAuth2)
      # auth garmin_cn/xoss/xingzhe: adapter.authenticate → SSO
      def auth(source)
        sources = %w[garmin garmin_cn xoss xingzhe]
        unless sources.include?(source)
          say_status :error, "Supported: #{sources.join(', ')}", :red
          return
        end

        if source == "garmin"
          say "Garmin international uses DI OAuth2 with MFA — handled by scripts/garmin_auth_local.sh:", :blue
          puts ""
          puts "  Initial setup (SSO + MFA):"
          puts "    ./scripts/garmin_auth_local.sh"
          puts ""
          puts "  Push cached token to auth_seed:"
          puts "    ./scripts/garmin_auth_local.sh --sync"
          puts ""
          puts "  The script will:"
          puts "    · Handle MFA via garmin_auth.py (curl_cffi)"
          puts "    · Update config/config.yml with Base64 auth_seed"
          puts "    · Optionally set GitHub Secret via gh CLI"
          puts ""
          puts "  CI uses auth_seed only — no email/password required."
          return
        end

        config = workouts_config.sync_config(source)
        if config.empty?
          say_status :warn, "No config for #{source}. Set env vars or config.yml", :yellow
          return
        end

        db = connect_db
        adapter = build_sync_adapter(source, db, nil)
        unless adapter.respond_to?(:authenticate)
          say_status :error, "#{source} does not support interactive auth", :red
          return
        end

        say_status :auth, "Logging in to #{source}...", :green
        if adapter.authenticate
          say_status :done, "#{source} authenticated successfully", :green
          if adapter.respond_to?(:generated_secret) && (secret = adapter.generated_secret)
            puts ""
            puts "GitHub Actions Secrets:"
            puts "  SYNC_#{source.upcase}_SECRET = #{secret}"
            puts "  SYNC_#{source.upcase}_EMAIL  = #{config["email"]}"
            puts "  SYNC_#{source.upcase}_PASSWORD = #{config["password"]}"
            puts ""
            puts "Local config:"
            puts "  #{source}:"
            puts "    secret: (已自动写入 config/config.yml)"
          end
        else
          say_status :error, "Authentication failed", :red
        end
      rescue Workouts::AuthError => e
        say_status :error, "Authentication failed: #{e.message}", :red
      end

      private

      def source_configured?(source)
        config = workouts_config.sync_config(source)
        case source
        when "strava"
          config["client_id"].to_s != "" && config["client_secret"].to_s != "" && config["refresh_token"].to_s != ""
        when "garmin"
          config["auth_seed"].to_s != ""
        when "garmin_cn"
          (config["email"].to_s != "" && config["password"].to_s != "") || config["secret"].to_s != ""
        when "keep"
          (config["phone"] || config["mobile"]).to_s != "" && config["password"].to_s != ""
        when "igpsport"
          config["phone"].to_s != "" && config["password"].to_s != ""
        when "xoss"
          config["email"].to_s != "" && config["password"].to_s != ""
        when "xingzhe"
          config["email"].to_s != "" && config["password"].to_s != ""
        when "apple_health"
          File.exist?("data/import/apple_health/export.zip")
        else
          config.values.any? { |v| v.to_s != "" }
        end
      end

      def build_sync_adapter(source, db, filter)
        config = workouts_config.sync_config(source)

        if source == "apple_health"
          return Workouts::Sync::AppleHealth.new(
            config: {}, db:, activity_filter: filter,
            time_budget: workouts_config.dig("sync", "time_budget")
          )
        end

        return nil if config.empty?

        klass = case source
                when "strava" then Workouts::Sync::Strava
                when "garmin" then Workouts::Sync::Garmin
                when "garmin_cn" then Workouts::Sync::GarminCN
                when "keep" then Workouts::Sync::Keep
                when "igpsport" then Workouts::Sync::IGPSPORT
                when "xoss" then Workouts::Sync::XOSS
                when "xingzhe" then Workouts::Sync::XingZhe
                else
                  say_status :error, "Unknown source: #{source}", :red
                  return nil
                end

        klass.new(config:, db:, activity_filter: filter, time_budget: workouts_config.dig("sync", "time_budget"))
      end
    end
  end
end

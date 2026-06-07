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

        sources.each do |source|
          say_status :syncing, source, :green
          adapter = build_sync_adapter(source, db, filter)
          next unless adapter

          begin
            count = adapter.call
            print "\r#{' ' * 60}\r"
            say_status :done, "#{source}: #{count} activities", :green
          rescue => e
            print "\r#{' ' * 60}\r"
            say_status :error, "#{source}: #{e.message}", :red
          end
        end
      end

      def auth(source)
        sources = %w[garmin garmin_cn xoss xingzhe]
        unless sources.include?(source)
          say_status :error, "Supported: #{sources.join(', ')}", :red
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
        else
          say_status :error, "Authentication failed", :red
        end
      end

      private

      def source_configured?(source)
        config = workouts_config.sync_config(source)
        case source
        when "strava"
          config["client_id"].to_s != "" && config["client_secret"].to_s != "" && config["refresh_token"].to_s != ""
        when "garmin", "garmin_cn"
          (config["email"].to_s != "" && config["password"].to_s != "") || config["secret"].to_s != ""
        when "keep"
          (config["phone"] || config["mobile"]).to_s != "" && config["password"].to_s != ""
        when "igpsport"
          config["phone"].to_s != "" && config["password"].to_s != ""
        when "xoss"
          config["email"].to_s != "" && config["password"].to_s != ""
        when "xingzhe"
          config["email"].to_s != "" && config["password"].to_s != ""
        else
          config.values.any? { |v| v.to_s != "" }
        end
      end

      def build_sync_adapter(source, db, filter)
        config = workouts_config.sync_config(source)
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

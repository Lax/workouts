module Workouts
  module Cli
    module Sync
      # auth garmin: delegated to git fit auth garmin (lib/workouts/cli.rb)
      # auth garmin_cn/xoss/xingzhe: adapter.authenticate → SSO
      def auth(source)
        sources = %w[garmin garmin_cn xoss xingzhe]
        unless sources.include?(source)
          say_status :error, "Supported: #{sources.join(", ")}", :red
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

      def build_sync_adapter(source, db, filter)
        config = workouts_config.sync_config(source)

        return nil if config.empty?

        klass = case source
        when "garmin_cn" then Workouts::Sync::GarminCN
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

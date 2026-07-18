module Workouts
  module Cli
    module Import
      def import(source = nil)
        source ||= options[:source]

        unless source == "apple_health"
          say_status :error, "Unknown import source: #{source || '(none)'}. Supported: apple_health", :red
          return
        end

        zip_path = Workouts::Import::AppleHealth::DEFAULT_ZIP_PATH
        unless File.exist?(zip_path)
          say_status :error, "Apple Health export not found at #{zip_path}. Upload via `serve start` first.", :red
          return
        end

        db = connect_db
        filter = options[:activity]&.map(&:strip)&.map(&:downcase)

        say_status :import, "apple_health", :green
        adapter = Workouts::Import::AppleHealth.new(
          config: {}, db:, activity_filter: filter,
          time_budget: workouts_config.dig("sync", "time_budget")
        )

        begin
          count = adapter.call
          if count == 0
            say_status :warn, "apple_health: 0 activities (already imported or none found)", :yellow
          else
            say_status :done, "apple_health: #{count} activities", :green
          end
        rescue => e
          say_status :error, "apple_health: #{e.message}", :red
        end
      end
    end
  end
end

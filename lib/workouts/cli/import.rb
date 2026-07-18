module Workouts
  module Cli
    module Import
      FILE_SOURCES = %w[gpx fit tcx].freeze

      def import
        sources = (options[:source] || "apple_health").split(",").map(&:strip).map(&:downcase)
        unknown = sources.reject { |s| s == "apple_health" || FILE_SOURCES.include?(s) }
        unless unknown.empty?
          say_status :error, "Unknown import source(s): #{unknown.join(', ')}. Supported: apple_health, gpx, fit, tcx", :red
          return
        end

        db = connect_db
        filter = options[:activity]&.map(&:strip)&.map(&:downcase)
        time_budget = workouts_config.dig("sync", "time_budget")

        total = 0

        if sources.include?("apple_health")
          total += import_apple_health(db, filter, time_budget)
        end

        file_sources = sources & FILE_SOURCES
        if file_sources.any?
          total += import_local_files(db, filter, time_budget, file_sources)
        end

        if total.zero?
          say_status :warn, "0 activities imported", :yellow
        else
          say_status :done, "#{total} activities imported", :green
        end
      end

      private

      def import_apple_health(db, filter, time_budget)
        zip_path = Workouts::Import::AppleHealth::DEFAULT_ZIP_PATH
        unless File.exist?(zip_path)
          say_status :error, "Apple Health export not found at #{zip_path}. Upload via `serve start` first.", :red
          return 0
        end

        say_status :import, "apple_health", :green
        adapter = Workouts::Import::AppleHealth.new(
          config: {}, db:, activity_filter: filter,
          time_budget: time_budget
        )

        begin
          count = adapter.call
          if count == 0
            say_status :warn, "apple_health: 0 activities (already imported or none found)", :yellow
          else
            say_status :done, "apple_health: #{count} activities", :green
          end
          count
        rescue => e
          say_status :error, "apple_health: #{e.message}", :red
          0
        end
      end

      def import_local_files(db, filter, time_budget, sources)
        sport_override = options[:sport]

        say_status :import, "local files (#{sources.join(', ')})", :green
        adapter = Workouts::Import::LocalFile.new(
          config: {}, db:, activity_filter: filter,
          time_budget: time_budget,
          sources: sources,
          sport_override: sport_override
        )

        begin
          adapter.call
        rescue => e
          say_status :error, "local_file: #{e.message}", :red
          0
        end
      end
    end
  end
end

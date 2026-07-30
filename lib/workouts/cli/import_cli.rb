require "thor"

module Workouts
  class ImportCLI < Thor
    FILE_SOURCES = %w[gpx fit tcx].freeze

    default_command :import

    desc "import", "Import workout data from local files (apple_health, gpx, fit, tcx)"
    option :source, type: :string, aliases: "-s",
      desc: "Import source(s) (apple_health, gpx, fit, tcx) — comma-separated"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    option :sport, type: :string, desc: "Override sport_category for GPX files"
    def import
      sources = (options[:source] || "apple_health").split(",").map(&:strip).map(&:downcase)
      unknown = sources.reject { |s| s == "apple_health" || FILE_SOURCES.include?(s) }
      unless unknown.empty?
        say_status :error, "Unknown import source(s): #{unknown.join(", ")}. Supported: apple_health, gpx, fit, tcx", :red
        return
      end

      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      time_budget = config.dig("sync", "time_budget")
      sport_override = options[:sport]

      total = 0

      if sources.include?("apple_health")
        total += run_apple_health(config, db, filter, time_budget)
      end

      file_sources = sources & FILE_SOURCES
      if file_sources.any?
        total += run_local_files(db, filter, time_budget, file_sources, sport_override)
      end

      if total.zero?
        say_status :warn, "0 activities imported", :yellow
      else
        say_status :done, "#{total} activities imported", :green
      end
    rescue => e
      say_status :error, "Import failed: #{e.message}", :red
    end

    desc "apple_health", "Import from Apple Health export.zip"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def apple_health
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      time_budget = config.dig("sync", "time_budget")
      run_apple_health(config, db, filter, time_budget)
    rescue => e
      say_status :error, "apple_health import failed: #{e.message}", :red
    end

    desc "gpx", "Import GPX files from data/import/gpx/"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    option :sport, type: :string, desc: "Override sport_category for GPX files"
    def gpx
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      time_budget = config.dig("sync", "time_budget")
      sport_override = options[:sport]
      run_local_files(db, filter, time_budget, ["gpx"], sport_override)
    rescue => e
      say_status :error, "gpx import failed: #{e.message}", :red
    end

    desc "fit", "Import FIT files from data/import/fit/"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def fit
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      time_budget = config.dig("sync", "time_budget")
      run_local_files(db, filter, time_budget, ["fit"], nil)
    rescue => e
      say_status :error, "fit import failed: #{e.message}", :red
    end

    desc "tcx", "Import TCX files from data/import/tcx/"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def tcx
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      time_budget = config.dig("sync", "time_budget")
      run_local_files(db, filter, time_budget, ["tcx"], nil)
    rescue => e
      say_status :error, "tcx import failed: #{e.message}", :red
    end

    no_commands do
      def run_apple_health(config, db, filter, time_budget)
        zip_path = Workouts::Import::AppleHealth::DEFAULT_ZIP_PATH
        unless File.exist?(zip_path)
          say_status :error, "Apple Health export not found at #{zip_path}. Upload via `serve start` first.", :red
          return 0
        end

        say_status :import, "apple_health", :green
        adapter = Workouts::Import::AppleHealth.new(
          config: config.dig("import", "apple_health") || {}, db:, activity_filter: filter,
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

      def run_local_files(db, filter, time_budget, sources, sport_override)
        say_status :import, "local files (#{sources.join(", ")})", :green
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

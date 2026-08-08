require "thor"

module Workouts
  class ExportCLI < Thor
    desc "json", "Export activities to JSON"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    option :tracks_output, type: :string, desc: "Separate tracks file (polyline map) for deferred loading"
    def json
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("json", "path") || "site/activities.json"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      tracks_output = options[:tracks_output]
      count = Export::JSON.new(db: db, output: path, activity_filter: filter, tracks_output: tracks_output).call
      if tracks_output
        say_status :done, "Exported #{count} activities → #{path} + tracks → #{tracks_output}", :green
      else
        say_status :done, "Exported #{count} activities to #{path}", :green
      end
    rescue => e
      say_status :error, "JSON export failed: #{e.message}", :red
    end

    desc "csv", "Export activities to CSV"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def csv
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("csv", "path") || "site/workouts.csv"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      Export::CSV.new(db: db, output: path, activity_filter: filter).call
      say_status :done, "Exported to #{path}", :green
    rescue => e
      say_status :error, "CSV export failed: #{e.message}", :red
    end

    desc "stats", "Export activity statistics"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def stats
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("stats", "path") || "site/stats.json"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      count = Export::Stats.new(db: db, output: path, activity_filter: filter).call
      say_status :done, "Exported stats for #{count} activities → #{path}", :green
    rescue => e
      say_status :error, "Stats export failed: #{e.message}", :red
    end

    desc "all", "Export all formats"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def all
      invoke :json, [], options
      invoke :csv, [], options
      invoke :stats, [], options
      say_status :done, "All exports complete", :green
    rescue => e
      say_status :error, "Export failed: #{e.message}", :red
    end
  end
end

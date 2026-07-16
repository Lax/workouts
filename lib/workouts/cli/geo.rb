require "thor"

module Workouts
  class GeoCLI < Thor
      desc "detect", "Detect administrative regions for activities with GPS data"
      option :limit,    type: :numeric, aliases: "-l", desc: "Max activities to process"
      option :batch,    type: :numeric, aliases: "-b", desc: "Batch size", default: 20
      option :strategy, type: :string,  aliases: "-s", desc: "Strategy: proportional|start_end", default: "proportional"
      option :time,     type: :numeric, aliases: "-t", desc: "Time budget in seconds"
      option :"dry-run", type: :boolean, desc: "Don't write to DB"
      def detect
        config = Workouts::Config.new
        db = Workouts::DB::Connection.new(config.db_path).db
        amap_key = ENV["AMAP_API_KEY"] || config.sync_config("amap")["api_key"]
        detector = Workouts::Geo::RegionDetector.new(
          db: db,
          amap_key: amap_key,
          batch: options[:batch],
          limit: options[:limit],
          strategy: options[:strategy],
          time_budget: options[:time],
          dry_run: options[:"dry-run"],
        )
        detector.run
      rescue => e
        say_status :error, "Geo detection failed: #{e.message}", :red
      end
  end
end

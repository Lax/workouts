require "thor"

module Workouts
  class MigrateCLI < Thor
    desc "igpsport_to_garmin", "Upload iGPSPORT activities to Garmin Connect (International)"
    option :dry, type: :boolean, default: false, desc: "List activities without uploading"
    option :since, type: :string, desc: "Upload only activities since date (YYYY-MM-DD)"
    option :limit, type: :numeric, desc: "Max activities to upload per run"
    def igpsport_to_garmin
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      garmin_config = config.sync_config("garmin")
      since = options[:since]
      limit = options[:limit] || ENV["MIGRATE__IGPSPORT_TO_GARMIN__LIMIT"]&.to_i || 10
      migrator = Migrate::IGPSportToGarmin.new(
        db: db, config: garmin_config,
        dry: options[:dry], since: since, limit: limit
      )
      count = migrator.call
      if options[:dry]
        say_status :done, "Listed #{count} activities", :green
      else
        say_status :done, "Uploaded #{count} iGPSPORT activities to Garmin", :green
      end
    rescue => e
      say_status :error, "igpsport_to_garmin failed: #{e.message}", :red
    end

    desc "igpsport_to_garmin_cn", "Upload iGPSPORT activities to Garmin Connect (China)"
    option :dry, type: :boolean, default: false, desc: "List activities without uploading"
    option :since, type: :string, desc: "Upload only activities since date (YYYY-MM-DD)"
    option :limit, type: :numeric, desc: "Max activities to upload per run"
    def igpsport_to_garmin_cn
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      garmin_config = config.sync_config("garmin_cn")
      since = options[:since]
      limit = options[:limit] || ENV["MIGRATE__IGPSPORT_TO_GARMIN_CN__LIMIT"]&.to_i || 10
      migrator = Migrate::IGPSportToGarminCN.new(
        db: db, config: garmin_config,
        dry: options[:dry], since: since, limit: limit
      )
      count = migrator.call
      if options[:dry]
        say_status :done, "Listed #{count} activities", :green
      else
        say_status :done, "Uploaded #{count} iGPSPORT activities to Garmin CN", :green
      end
    rescue => e
      say_status :error, "igpsport_to_garmin_cn failed: #{e.message}", :red
    end
  end
end

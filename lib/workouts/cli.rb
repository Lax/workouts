module Workouts
  require_relative "cli/export"
  require_relative "cli/sync"

  class CLI < Thor
    package_name "Workouts"

    class_option :config, type: :string, desc: "Path to config file", aliases: "-c"
    class_option :db, type: :string, desc: "Database path override"

    def self.exit_on_failure?
      true
    end

    include Cli::Sync

    desc "sync", "Sync workout data from configured sources"
    option :source, type: :string, desc: "Sync only specific source (strava/garmin/keep/igpsport/xoss)"
    option :activity, type: :array, desc: "Filter by sport type (run,ride,hike,...)", aliases: "--act"
    def sync
      super
    end

    desc "auth SOURCE", "Authenticate with a sync source (strava, garmin, garmin_cn)"
    def auth(source)
      if source == "strava"
        Auth::Strava.new(options, workouts_config).call
      else
        super
      end
    rescue Workouts::AuthError => e
      say_status :error, "Auth failed: #{e.message}", :red
    rescue => e
      say_status :error, e.message, :red
    end

    no_commands do
      def workouts_config
        @workouts_config ||= begin
          cfg = respond_to?(:options) ? options[:config] : nil
          cfg = cfg.to_s if cfg
          Workouts::Config.new(cfg)
        end
      end

      def db_path
        (respond_to?(:options) ? options[:db] : nil) || workouts_config.db_path
      end
    end

    desc "export SUBCOMMAND", "Export activities to various formats"
    subcommand "export", ExportCLI

    desc "migrate", "Run database migrations"
    def migrate
      connect_db
      say_status :done, "Migrations up to date", :green
    rescue => e
      say_status :error, "Migration failed: #{e.message}", :red
    end

    desc "init", "Generate default config.yml"
    def init
      path = options[:output] || "config/config.yml"
      File.write(path, ConfigTemplate.generate)
      say_status :created, path, :green
    end

    desc "parse FILE", "Parse a GPX or TCX file and optionally save to DB"
    option :save, type: :boolean, desc: "Save parsed activities to database", aliases: "-s"
    option :dry, type: :boolean, default: true, desc: "Print parsed data without saving"
    def parse(file)
      format = case file
               when /\.gpx$/i then :gpx
               when /\.tcx$/i then :tcx
               else
                 say_status :error, "Unsupported format (use .gpx or .tcx)", :red
                 return
               end

      content = File.read(file)
      parser = format == :gpx ? Parser::GPX.new(source: "file") : Parser::TCX.new(source: "file")
      activities = parser.call(content)

      if activities.empty?
        say_status :warn, "No activities found in #{file}", :yellow
        return
      end

      activities.each do |act|
        say_status :activity, act[:name] || "unnamed", :green
        say "  Sport: #{act[:sport_category]}#{act[:sport_type] ? " (#{act[:sport_type]})" : ""}"
        say "  Date:  #{act[:start_date]}"
        say "  Dist:  #{act[:distance]&.round(2)}m" if act[:distance]
        say "  Time:  #{act[:moving_time]}s" if act[:moving_time]
        say "  HR:    #{act[:average_heartrate]}" if act[:average_heartrate]
        say "  Elev:  #{act[:elevation_gain]}m" if act[:elevation_gain]
      end

      if options[:save]
        db = connect_db
        now = Time.now.utc
        activities.each do |act|
          existing = db[:activities].where(run_id: act[:run_id]).first
          if existing
            db[:activities].where(run_id: act[:run_id]).update(act.merge(updated_at: now))
          else
            db[:activities].insert(act.merge(created_at: now, updated_at: now))
          end
        end
        say_status :done, "Saved #{activities.size} activities to database", :green
      end
    rescue => e
      say_status :error, "Parse failed: #{e.message}", :red
    end

    desc "version", "Show version"
    def version
      puts "Workouts v#{Workouts::VERSION}"
    end

    private

    def connect_db
      Workouts::DB::Connection.new(db_path).db
    end
  end
end

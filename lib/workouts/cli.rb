module Workouts
  class ExportCLI < Thor
    desc "json", "Export activities to JSON"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def json
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("json", "path") || "data/activities.json"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      count = Export::JSON.new(db: db, output: path, activity_filter: filter).call
      say_status :done, "Exported #{count} activities to #{path}", :green
    end

    desc "csv", "Export activities to CSV"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def csv
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("csv", "path") || "data/workouts.csv"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      Export::CSV.new(db: db, output: path, activity_filter: filter).call
      say_status :done, "Exported to #{path}", :green
    end

    desc "svg", "Generate SVG poster"
    option :style, type: :string, required: true, desc: "Poster style: github/grid/circular/month-of-life/year-summary"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    option :year, type: :string, desc: "Filter by year (YYYY or 'all')"
    option :title, type: :string, desc: "Poster title"
    option :athlete, type: :string, desc: "Athlete name"
    option :bg_color, type: :string, desc: "Background color (--bg-color)", default: "#222222"
    option :track_color, type: :string, desc: "Activity color (--track-color)", default: "#4DD2FF"
    option :special_color, type: :string, desc: "Special activity color (--special-color)", default: "#FFFF00"
    option :text_color, type: :string, desc: "Text color (--text-color)", default: "#FFFFFF"
    option :special_distance, type: :numeric, desc: "Special distance 1 in km (--special-distance)", default: 10
    option :special_distance2, type: :numeric, desc: "Special distance 2 in km (--special-distance2)", default: 20
    option :min_distance, type: :numeric, desc: "Minimum distance in km (--min-distance)", default: 0
    option :birth, type: :string, desc: "Birth date (YYYY-MM) for month-of-life style"
    option :summary_year, type: :numeric, desc: "Year for summary style (--summary-year)"
    option :color_run, type: :string, desc: "Color for run activities (--color-run)", default: "#4DD2FF"
    option :color_ride, type: :string, desc: "Color for ride activities (--color-ride)", default: "#FF6B6B"
    option :color_walk, type: :string, desc: "Color for walk activities (--color-walk)", default: "#4ECDC4"
    def svg
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      svg_dir = config.export_config.dig("svg", "dir") || "data/svg"
      path = options[:output] || "#{svg_dir}/#{options[:style]}.svg"

      style = options[:style]
      unless Workouts::Export::SVG::STYLES.include?(style)
        say_status :error, "Unknown style: #{style}. Available: #{Workouts::Export::SVG::STYLES.join(', ')}", :red
        return
      end

      if style == "month-of-life" && !options[:birth]
        say_status :error, "--birth YYYY-MM is required for month-of-life style", :red
        return
      end

      FileUtils.mkdir_p(File.dirname(path))

      svg_gen = Workouts::Export::SVG::Renderer.new(
        db: db,
        style: style,
        output: path,
        year: options[:year] || "all",
        title: options[:title],
        athlete: options[:athlete],
        bg_color: options[:bg_color] || "#222222",
        track_color: options[:track_color] || "#4DD2FF",
        special_color: options[:special_color] || "#FFFF00",
        text_color: options[:text_color] || "#FFFFFF",
        special_distance: options[:special_distance] || 10,
        special_distance2: options[:special_distance2] || 20,
        min_distance: options[:min_distance] || 0,
        activity_filter: options[:activity]&.map(&:strip)&.map(&:downcase),
        birth: options[:birth],
        summary_year: options[:summary_year],
        color_run: options[:color_run],
        color_ride: options[:color_ride],
        color_walk: options[:color_walk]
      )

      count = svg_gen.call
      say_status :done, "Generated #{style} poster with #{count} activities → #{path}", :green
    end

    desc "all", "Export all formats"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def all
      invoke :json, [], options
      invoke :csv, [], options
      say_status :done, "All exports complete", :green
    end
  end

  class CLI < Thor
    package_name "Workouts"

    class_option :config, type: :string, desc: "Path to config file", aliases: "-c"
    class_option :db, type: :string, desc: "Database path override"

    def self.exit_on_failure?
      true
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

    desc "sync", "Sync workout data from configured sources"
    option :source, type: :string, desc: "Sync only specific source (strava/garmin/keep/igpsport/xoss)"
    option :activity, type: :array, desc: "Filter by sport type (run,ride,hike,...)", aliases: "--act"
    def sync
      db = connect_db
      sources = if options[:source]
                  [options[:source]]
                else
                  %w[strava garmin keep igpsport xoss xingzhe].select do |s|
                    source_configured?(s)
                  end
                end

      filter = options[:activity]&.map(&:strip)&.map(&:downcase)

      sources.each do |source|
        say_status :syncing, source, :green
        adapter = build_sync_adapter(source, db, filter)
        next unless adapter

        count = adapter.call
        print "\r#{' ' * 60}\r"
        say_status :done, "#{source}: #{count} activities", :green
      end
    end

    desc "export SUBCOMMAND", "Export activities to various formats"
    subcommand "export", ExportCLI

    desc "migrate", "Run database migrations"
    def migrate
      connect_db
      say_status :done, "Migrations up to date", :green
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
    end

    desc "auth SOURCE", "Authenticate with a sync source (garmin, garmin_cn)"
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

    desc "version", "Show version"
    def version
      puts "Workouts v#{Workouts::VERSION}"
    end

    private

    def source_configured?(source)
      config = workouts_config.sync_config(source)
      config.values.any? { |v| v.to_s != "" }
    end

    def connect_db
      Workouts::DB::Connection.new(db_path).db
    end

    def build_sync_adapter(source, db, filter)
      config = workouts_config.sync_config(source)
      return nil if config.empty?

      klass = case source
              when "strava" then Sync::Strava
              when "garmin" then Sync::Garmin
              when "garmin_cn" then Sync::GarminCN
              when "keep" then Sync::Keep
              when "igpsport" then Sync::IGPSPORT
              when "xoss" then Sync::XOSS
              when "xingzhe" then Sync::XingZhe
              else
                say_status :error, "Unknown source: #{source}", :red
                return nil
              end

      klass.new(config: config, db: db, activity_filter: filter)
    end
  end
end

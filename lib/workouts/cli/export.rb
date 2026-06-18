require "thor"

module Workouts
  class ExportCLI < Thor
    desc "json", "Export activities to JSON"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def json
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("json", "path") || "build/activities.json"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      count = Export::JSON.new(db: db, output: path, activity_filter: filter).call
      say_status :done, "Exported #{count} activities to #{path}", :green
    rescue => e
      say_status :error, "JSON export failed: #{e.message}", :red
    end

    desc "csv", "Export activities to CSV"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def csv
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("csv", "path") || "build/workouts.csv"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      Export::CSV.new(db: db, output: path, activity_filter: filter).call
      say_status :done, "Exported to #{path}", :green
    rescue => e
      say_status :error, "CSV export failed: #{e.message}", :red
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
      svg_dir = config.export_config.dig("svg", "dir") || "build/svg"
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
        db: db, style: style, output: path, year: options[:year] || "all",
        title: options[:title], athlete: options[:athlete],
        bg_color: options[:bg_color] || "#222222", track_color: options[:track_color] || "#4DD2FF",
        special_color: options[:special_color] || "#FFFF00", text_color: options[:text_color] || "#FFFFFF",
        special_distance: options[:special_distance] || 10, special_distance2: options[:special_distance2] || 20,
        min_distance: options[:min_distance] || 0,
        activity_filter: options[:activity]&.map(&:strip)&.map(&:downcase),
        birth: options[:birth], summary_year: options[:summary_year],
        color_run: options[:color_run], color_ride: options[:color_ride], color_walk: options[:color_walk]
      )

      count = svg_gen.call
      say_status :done, "Generated #{style} poster with #{count} activities → #{path}", :green
    rescue => e
      say_status :error, "SVG export failed: #{e.message}", :red
    end

    desc "stats", "Export activity statistics"
    option :output, type: :string, aliases: "-o", desc: "Output path"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def stats
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      path = options[:output] || config.export_config.dig("stats", "path") || "build/stats.json"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      count = Export::Stats.new(db: db, output: path, activity_filter: filter).call
      say_status :done, "Exported stats for #{count} activities → #{path}", :green
    rescue => e
      say_status :error, "Stats export failed: #{e.message}", :red
    end

    desc "dashboard", "Generate interactive dashboard (index.html + JSON data)"
    option :output, type: :string, aliases: "-o", desc: "Output directory"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def dashboard
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      outdir = options[:output] || "build"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      count = Export::Dashboard.new(db: db, output: outdir, activity_filter: filter).call
      say_status :done, "Generated interactive dashboard for #{count} activities → #{outdir}/", :green
    rescue => e
      say_status :error, "Dashboard export failed: #{e.message}", :red
    end

    desc "gpx", "Export activities to GPX files (one per activity)"
    option :output, type: :string, aliases: "-o", desc: "Output directory"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def gpx
      config = Workouts::Config.new
      db = Workouts::DB::Connection.new(config.db_path).db
      outdir = options[:output] || config.export_config.dig("gpx", "path") || "build/gpx_out"
      filter = options[:activity]&.map(&:strip)&.map(&:downcase)
      count = Export::GPX.new(db: db, output: outdir, activity_filter: filter).call
      say_status :done, "Exported #{count} GPX files to #{outdir}/", :green
    rescue => e
      say_status :error, "GPX export failed: #{e.message}", :red
    end

    desc "html", "Generate HTML site (delegates to dashboard)"
    option :output, type: :string, aliases: "-o", desc: "Output directory"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def html
      invoke :dashboard, [], options
    end

    desc "all", "Export all formats"
    option :activity, type: :array, desc: "Filter by sport type", aliases: "--act"
    def all
      invoke :json, [], options
      invoke :csv, [], options
      invoke :stats, [], options
      invoke :dashboard, [], options
      invoke :gpx, [], options
      say_status :done, "All exports complete", :green
    rescue => e
      say_status :error, "Export failed: #{e.message}", :red
    end
  end
end

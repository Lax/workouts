require "fileutils"

module Workouts
  module Export
    module SVG
      class Renderer
        def initialize(db:, style:, output:, year: nil, title: nil, athlete: nil,
                       bg_color: "#222222", track_color: "#4DD2FF",
                       special_color: "#FFFF00", text_color: "#FFFFFF",
                       special_distance: 10, special_distance2: 20,
                       min_distance: 0, activity_filter: nil,
                       birth: nil, summary_year: nil, github_style: "align-firstday",
                       color_run: nil, color_ride: nil, color_walk: nil)
          @db = db
          @style = style
          @output = output
          @year = year
          @title = title || "My Workouts"
          @athlete = athlete || "Athlete"
          @colors = {
            background: bg_color,
            track: track_color,
            track2: track_color,
            special: special_color,
            special2: special_color,
            text: text_color
          }
          @special_distance = { special_distance: special_distance, special_distance2: special_distance2 }
          @min_distance = min_distance
          @activity_filter = activity_filter
          @birth = birth
          @summary_year = summary_year
          @color_run = color_run
          @color_ride = color_ride
          @color_walk = color_walk
          @github_style = github_style
        end

        def call
          activities = load_activities
          return 0 if activities.empty?

          drawer = build_drawer
          return 0 unless drawer

          years = collect_years(activities)
          tracks = build_tracks(activities, years)

          if @style == "circular"
            generate_circular_multi(tracks, drawer, years)
          elsif @style == "year-summary" && !@summary_year
            generate_yearly_multi(tracks, drawer, "#{File.dirname(@output)}/year_summary_", years)
          elsif @style == "github" && @year == "all" && @github_style == "all-years"
            generate_yearly_multi(tracks, drawer, "#{File.dirname(@output)}/github_", years)
          else
            generate_single(tracks, drawer)
          end

          activities.size
        end

        private

        def load_activities
          ds = @db[:activities]
          ds = ds.where(sport_category: @activity_filter) if @activity_filter
          ds.order(Sequel.desc(:start_date)).all
        end

        def collect_years(activities)
          years = activities.map { |a| a[:start_date] && a[:start_date][0..3].to_i }.compact.uniq.sort
          years = [@year.to_i] if @year && @year != "all"
          years
        end

        def build_tracks(activities, years)
          min_dist_m = @min_distance * 1000

          activities.filter_map do |a|
            start_date = a[:start_date]
            next unless start_date

            year = start_date[0..3].to_i
            next unless years.include?(year)

            dist = a[:distance] || 0
            next if dist < min_dist_m

            Track.new(a, @colors, @special_distance)
          end
        end

        def build_drawer
          poster = Poster.new(@title, @athlete, @colors, @special_distance)
          poster.github_style = @github_style
          poster.color_by_category["run"] = @color_run if @color_run
          poster.color_by_category["ride"] = @color_ride if @color_ride
          poster.color_by_category["walk"] = @color_walk if @color_walk

          case @style
          when "github" then GithubDrawer.new(poster)
          when "grid" then GridDrawer.new(poster)
          when "circular" then CircularDrawer.new(poster)
          when "month-of-life" then MonthOfLifeDrawer.new(poster, @birth)
          when "year-summary"
            drawer = YearSummaryDrawer.new(poster)
            drawer.year = @summary_year || Time.now.year
            drawer
          else nil
          end
        end

        def generate_single(tracks, drawer)
          poster = drawer.poster
          poster.tracks = tracks
          poster.drawer_type = drawer_type_for_style
          poster.width = 200
          poster.height = @style == "github" ? 55 + tracks.map(&:year).uniq.size * 43 : 300
          render_svg(poster, drawer, @output)
        end

        def generate_circular_multi(tracks, drawer, years)
          output_dir = File.dirname(@output)
          FileUtils.mkdir_p(output_dir)
          years.each do |year|
            poster = drawer.poster
            poster.drawer_type = "plain"
            poster.width = 200
            poster.height = 300
            poster.tracks = tracks.select { |t| t.year == year }
            next if poster.tracks.empty?
            render_svg(poster, drawer, File.join(output_dir, "year_#{year}.svg"))
          end
        end

        def generate_yearly_multi(tracks, drawer, prefix, years)
          FileUtils.mkdir_p(File.dirname(prefix))
          years.each do |year|
            poster = drawer.poster
            poster.drawer_type = "year_summary"
            poster.width = 200
            poster.height = 300
            drawer.year = year if drawer.respond_to?(:year=)
            poster.tracks = tracks.select { |t| t.year == year }
            next if poster.tracks.empty?
            render_svg(poster, drawer, "#{prefix}#{year}.svg")
          end
        end

        def drawer_type_for_style
          case @style
          when "circular" then "plain"
          when "month-of-life" then "monthoflife"
          when "year-summary" then "year_summary"
          else "title"
          end
        end

        def render_svg(poster, drawer, output_path)
          FileUtils.mkdir_p(File.dirname(output_path))
          lines = []
          lines << %(<?xml version="1.0" encoding="UTF-8"?>)
          lines << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{poster.width}mm" height="#{poster.height}mm" viewBox="0 0 #{poster.width} #{poster.height}">)
          lines << tag("rect", { x: 0, y: 0, width: poster.width, height: poster.height, fill: poster.colors[:background] })

          if poster.drawer_type != "plain"
            lines << draw_header(poster)
            lines << drawer.draw([], [poster.width - 20, poster.height - 30 - 30], [10, 30])
            lines << draw_footer(poster)
          else
            lines << drawer.draw([], [poster.width - 20, poster.height], [10, 0])
          end

          lines << "</svg>"
          File.write(output_path, lines.join("\n"))
        end

        def draw_header(poster)
          style = "font-size:12px; font-family:Arial; font-weight:bold;"
          tag("text", { x: 10, y: 20, fill: poster.colors[:text], style: style }, poster.title)
        end

        def draw_footer(poster)
          lines = []
          tc = poster.colors[:text]
          hdr = "font-size:4px; font-family:Arial"
          val = "font-size:9px; font-family:Arial"
          sm = "font-size:3px; font-family:Arial"
          h = poster.height
          sd1 = poster.special_distance[:special_distance]
          sd2 = poster.special_distance[:special_distance2]

          total_len = poster.tracks.sum(&:length)
          avg_len = poster.tracks.empty? ? 0 : total_len / poster.tracks.size
          weeks = poster.tracks.map { |t| [t.year, t.date.to_date.cweek] }.uniq.size
          weeks = 1 if weeks < 1

          lines << tag("text", { x: 10, y: h - 20, fill: tc, style: hdr }, "Runner")
          lines << tag("text", { x: 10, y: h - 10, fill: tc, style: val }, poster.athlete)

          unless poster.drawer_type == "monthoflife"
            lines << tag("text", { x: 65, y: h - 20, fill: tc, style: hdr }, "BREAKDOWN")
            cats = %w[run ride walk]
            y = h - 17
            cats.each do |cat|
              t = poster.tracks.select { |tr| tr.sport_category == cat }
              next if t.empty?
              color = poster.color_by_category[cat] || poster.colors[:track]
              total = t.sum(&:length)
              lines << tag("rect", { x: 65, y: y, width: 2.6, height: 2.6, fill: color })
              lines << tag("text", { x: 70, y: y + 2, fill: tc, style: sm },
                "#{cat}  #{t.size}  #{format_float(poster.m2u(total))}#{poster.u}")
              if cat == "ride"
                cad = t.map(&:average_cadence).compact
                pow = t.map(&:average_power).compact
                extras = []
                extras << "#{format_float(cad.sum / cad.size)}rpm" if cad.any?
                extras << "#{format_float(pow.sum / pow.size)}W" if pow.any?
                unless extras.empty?
                  lines << tag("text", { x: 70, y: y + 5, fill: tc, style: sm }, extras.join(" "))
                end
              end
              y += cat == "ride" && t.any? { |tr| tr.average_cadence || tr.average_power } ? 6 : 3
            end
          end

          lines << tag("text", { x: 120, y: h - 20, fill: tc, style: hdr }, "STATISTICS")
          lines << tag("text", { x: 120, y: h - 15, fill: tc, style: sm }, "Number: #{poster.tracks.size}")
          lines << tag("text", { x: 120, y: h - 10, fill: tc, style: sm }, "Weekly: #{format_float(poster.tracks.size.to_f / weeks)}")
          lines << tag("text", { x: 141, y: h - 15, fill: tc, style: sm }, "Total: #{format_float(poster.m2u(total_len))} #{poster.u}")
          lines << tag("text", { x: 141, y: h - 10, fill: tc, style: sm }, "Avg: #{format_float(poster.m2u(avg_len))} #{poster.u}")
          lines.join("\n")
        end

        def tag(name, attrs = {}, content = nil)
          attr_str = attrs.map { |k, v| %( #{k}="#{escape(v)}") }.join
          if content
            "<#{name}#{attr_str}>#{escape(content)}</#{name}>"
          else
            "<#{name}#{attr_str} />"
          end
        end

        def escape(str)
          str.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
        end

        def format_float(f)
          f.is_a?(Float) ? format("%.1f", f) : f.to_s
        end
      end
    end
  end
end

module Workouts
  module Export
    module SVG
      class YearSummaryDrawer < BaseDrawer
        attr_accessor :year

        def draw(doc, size, offset)
          return "" unless poster.tracks&.any?

          lines = []
          tc = poster.colors[:text]
          dim = "#555555"
          track_c = poster.colors[:track]
          special_c = poster.colors[:special]

          year_tracks = poster.tracks.select { |t| t.year == (@year || Time.now.year) }
          stats = calculate_stats(year_tracks)

          left_margin = offset[0] + 6
          left_width = size[0] * 0.40
          right_start = offset[0] + left_width

          header_text = stats[:first_run] ? "Running for #{stats[:days_ago]} Days" : "Year #{@year}"
          lines << tag("text", { x: left_margin, y: offset[1] + 14, fill: dim, style: "font-size:6px;font-family:Arial;" }, header_text)

          lines << tag("text", { x: left_margin, y: offset[1] + 34, fill: dim, style: "font-size:6px;font-family:Arial;" }, "Races")

          categories = [
            ["Full", stats[:marathon_count]],
            ["Half", stats[:half_marathon_count]],
            ["10K", stats[:"10k_count"]]
          ]

          y_pos = offset[1] + 54
          race_num = 1
          race_count = 0

          categories.each do |name, count|
            next unless count > 0

            lines << tag("text", { x: left_margin, y: y_pos, fill: dim, style: "font-size:8px;font-family:Arial;" }, race_num.to_s)
            lines << tag("text", { x: left_margin + 12, y: y_pos, fill: tc, style: "font-size:10px;font-family:Arial;font-weight:bold;" }, name)
            lines << tag("text", { x: left_margin + 38, y: y_pos, fill: dim, style: "font-size:6px;font-family:Arial;" }, "#{count}x")
            y_pos += 18
            race_num += 1
            race_count += 1
          end

          stats_start_y = race_count == 0 ? offset[1] + 72 : offset[1] + 54 + race_count * 18 + 26
          lines << tag("text", { x: left_margin, y: stats_start_y - 6, fill: dim, style: "font-size:6px;font-family:Arial;" }, "Stats")

          total_hours = (stats[:total_time] / 3600).to_i
          avg_pace = stats[:avg_pace]

          stat_items = [
            ["Distance", stats[:total_distance].to_s, poster.u],
            ["Runs", stats[:total_runs].to_s, ""],
            ["Avg Pace", avg_pace, ""],
            ["Streak", stats[:streak].to_s, "d"],
            ["Time", total_hours.to_s, "h"],
            ["Longest", format("%.1f", stats[:longest_run]), ""]
          ]

          col1_x = left_margin
          col2_x = left_margin + 42

          stat_items.each_with_index do |(label, value, unit), i|
            x = i.even? ? col1_x : col2_x
            sy = stats_start_y + (i / 2) * 28

            lines << tag("text", { x: x, y: sy, fill: dim, style: "font-size:5px;font-family:Arial;" }, label)
            lines << tag("text", { x: x, y: sy + 11, fill: tc, style: "font-size:10px;font-family:Arial;font-weight:bold;" }, value)
            if unit && !unit.empty?
              vw = value.length * 6
              lines << tag("text", { x: x + vw, y: sy + 11, fill: dim, style: "font-size:6px;font-family:Arial;" }, unit)
            end
          end

          dots_y_start = offset[1] + 8
          dots_height = size[1] - 16
          dots_spacing_y = dots_height / 31.0

          runner_row = dots_y_start + 27.5 * dots_spacing_y
          lines << tag("text", { x: left_margin, y: runner_row - 4, fill: dim, style: "font-size:5px;font-family:Arial;" }, "Runner")
          lines << tag("text", { x: left_margin, y: runner_row + 6, fill: tc, style: "font-size:8px;font-family:Arial;font-weight:bold;" }, poster.athlete)

          footer_y = dots_y_start + 30.5 * dots_spacing_y + 3
          lines << tag("text", { x: left_margin, y: footer_y, fill: dim, style: "font-size:7px;font-family:Arial;" }, "workouts/#{@year}")

          lines << draw_monthly_grid(year_tracks, right_start, offset[1] + 8,
                                     size[0] - (right_start - offset[0]) - 8,
                                     size[1] - 16, track_c, special_c, dim)

          lines.join("\n")
        end

        private

        def draw_monthly_grid(tracks, x_start, y_start, width, height, track_c, special_c, dim)
          lines = []
          cols, rows = 12, 31
          spacing_x = width.to_f / cols
          spacing_y = height.to_f / rows
          radius = [spacing_x, spacing_y].min / 2 * 0.75

          month_data = Hash.new { |h, k| h[k] = Hash.new(0.0) }
          tracks.each do |t|
            month_data[t.date.month][t.date.day] += poster.m2u(t.length)
          end

          max_dist = 1
          month_data.each_value { |days| days.each_value { |d| max_dist = [max_dist, d].max } }
          sd = poster.special_distance[:special_distance]

          (1..12).each do |month|
            (1..31).each do |day|
              begin
                Date.new(@year || Time.now.year, month, day)
              rescue ArgumentError
                next
              end

              cx = x_start + (month - 1) * spacing_x + spacing_x / 2
              cy = y_start + (day - 1) * spacing_y + spacing_y / 2
              dist = month_data[month][day]

              color = if dist > 0
                        if dist >= sd
                          special_c
                        else
                          intensity = max_dist > 0 ? [dist / sd, 1.0].min : 0
                          interpolate_color(dim, track_c, intensity)
                        end
                      else
                        dim
                      end

              title = "#{@year}-#{format('%02d', month)}-#{format('%02d', day)}"
              title += ": #{format('%.1f', dist)} #{poster.u}" if dist > 0
              lines << %(<g><title>#{escape(title)}</title><circle cx="#{cx}" cy="#{cy}" r="#{radius}" fill="#{color}" /></g>)
            end
          end

          lines.join("\n")
        end

        def calculate_stats(tracks)
          stats = { total_runs: tracks.size, total_distance: 0, marathon_count: 0,
                    half_marathon_count: 0, :"10k_count" => 0, avg_pace: "0'00\"",
                    streak: 0, total_time: 0, longest_run: 0, first_run: nil, days_ago: 0 }

          return stats if tracks.empty?

          total_dist = 0.0
          total_time_s = 0.0
          longest = 0.0

          tracks.each do |t|
            dist_km = poster.m2u(t.length)
            total_dist += poster.m2u(t.length)

            stats[:marathon_count] += 1 if dist_km >= 42.0
            stats[:half_marathon_count] += 1 if dist_km >= 21.0 && dist_km < 42.0
            stats[:"10k_count"] += 1 if dist_km >= 10.0 && dist_km < 21.0

            total_time_s += t.moving_time if t.moving_time
            longest = [longest, poster.m2u(t.length)].max
          end

          stats[:total_distance] = total_dist
          stats[:total_time] = total_time_s
          stats[:longest_run] = longest

          if total_dist > 0 && total_time_s > 0
            pace_s = total_time_s / total_dist
            pace_min = (pace_s / 60).to_i
            pace_sec = (pace_s % 60).to_i
            stats[:avg_pace] = "#{pace_min}'#{format('%02d', pace_sec)}\""
          end

          stats[:streak] = calculate_streak(tracks)

          dates = tracks.map(&:date).sort
          if dates.any?
            stats[:first_run] = dates.first
            stats[:days_ago] = ((Time.now - dates.first.to_time) / 86400).to_i
          end

          stats
        end

        def calculate_streak(tracks)
          dates = tracks.map { |t| t.date.to_date }.uniq.sort
          return 0 if dates.empty?

          max_s = 1
          cur = 1
          (1...dates.size).each do |i|
            if (dates[i] - dates[i - 1]).to_i == 1
              cur += 1
              max_s = [max_s, cur].max
            else
              cur = 1
            end
          end
          max_s
        end

        def interpolate_color(...)
          super
        end

        def format(...)
          Kernel.format(...)
        end
      end
    end
  end
end

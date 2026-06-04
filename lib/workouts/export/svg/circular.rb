module Workouts
  module Export
    module SVG
      class CircularDrawer < BaseDrawer
        def draw(doc, size, offset)
          return "" unless poster.tracks&.any?

          lines = []
          track_by_date = group_by_date
          length_range_by_date = compute_length_range(track_by_date)
          return "" if length_range_by_date.zero?

          years_list = poster.tracks.map(&:year).uniq.sort
          counts = compute_grid(years_list.size, size)
          return "" unless counts

          count_x, count_y = counts[0], counts[1]
          x, y = 0, 0
          cell_size = [size[0] / count_x, size[1] / count_y]
          margin = [4, 4]
          margin = [0, 0] if count_x <= 1
          sub_size = [cell_size[0] - 2 * margin[0], cell_size[1] - 2 * margin[1]]

          years_list.each do |year|
            cx = offset[0] + margin[0] + cell_size[0] * x
            cy = offset[1] + margin[1] + cell_size[1] * y
            lines << draw_year(track_by_date, length_range_by_date, sub_size, [cx, cy], year)
            x += 1
            if x >= count_x
              x = 0
              y += 1
            end
          end

          lines.join("\n")
        end

        private

        def draw_year(track_by_date, length_range, size, offset, year)
          lines = []
          min_size = [size[0], size[1]].min
          outer_radius = 0.5 * min_size - 6
          rr_lower = outer_radius / 4
          rr_upper = outer_radius
          center = [offset[0] + size[0] / 2, offset[1] + size[1] / 2]

          yr_style = "dominant-baseline:central;font-size:#{min_size * 4.0 / 80.0}px;font-family:Arial;"
          mo_style = "font-size:#{min_size * 3.0 / 80.0}px;font-family:Arial;"

          lines << tag("text", { x: center[0], y: center[1], fill: poster.colors[:text], "text-anchor" => "middle", "alignment-baseline" => "middle", style: yr_style }, year.to_s)

          df = 360.0 / (Date.leap?(year) ? 366 : 365)
          day_num = 0
          date = Date.new(year, 1, 1)

          while date.year == year
            date_key = date.to_s
            a1 = df * day_num * Math::PI / 180.0
            a2 = df * (day_num + 1) * Math::PI / 180.0

            if date.day == 1
              last_day = Date.new(date.year, date.month, -1).day
              a3 = df * (day_num + last_day - 1) * Math::PI / 180.0
              r1 = outer_radius + 1
              r2 = outer_radius + 6
              r3 = outer_radius + 2

              sin_a1, cos_a1 = Math.sin(a1), Math.cos(a1)
              sin_a3, cos_a3 = Math.sin(a3), Math.cos(a3)

              lines << tag("line", {
                x1: center[0] + r1 * sin_a1, y1: center[1] - r1 * cos_a1,
                x2: center[0] + r2 * sin_a1, y2: center[1] - r2 * cos_a1,
                stroke: poster.colors[:text], "stroke-width" => 0.3
              })

              mid_a = (a1 + a3) / 2
              mid_r = r3 + 1
              mid_x = center[0] + mid_r * Math.sin(mid_a)
              mid_y = center[1] - mid_r * Math.cos(mid_a)
              lines << tag("text", {
                x: mid_x, y: mid_y,
                fill: poster.colors[:text],
                "text-anchor" => "middle",
                "font-size" => "#{min_size * 3.0 / 80.0}px",
                "font-family" => "Arial"
              }, Date::MONTHNAMES[date.month])
            end

            if track_by_date[date_key]
              total_len = track_by_date[date_key].sum(&:length)
              t = length_range.zero? ? 0 : total_len / length_range.to_f
              color = interpolate_color("#444444", poster.colors[:track], [t, 1.0].min)

              r1c = rr_lower
              r2c = rr_lower + (rr_upper - rr_lower) * total_len / length_range

              sin_a1, cos_a1 = Math.sin(a1), Math.cos(a1)
              sin_a2, cos_a2 = Math.sin(a2), Math.cos(a2)

              d = "M #{center[0] + r1c * sin_a1},#{center[1] - r1c * cos_a1} "
              d += "l #{(r2c - r1c) * sin_a1},#{(r1c - r2c) * cos_a1} "
              d += "a #{r2c},#{r2c} 0 0,0 #{r2c * (sin_a2 - sin_a1)},#{r2c * (cos_a1 - cos_a2)} "
              d += "l #{(r1c - r2c) * sin_a2},#{(r2c - r1c) * cos_a2}"

              dist_km = poster.m2u(total_len)
              title = "#{date_key} #{format('%.1f', dist_km)} #{poster.u}"
              lines << %(<g><title>#{escape(title)}</title><path d="#{d}" fill="#{color}" stroke="none" /></g>)
            end

            day_num += 1
            date += 1
          end

          lines.join("\n")
        end

        def group_by_date
          h = {}
          poster.tracks.each { |t| (h[t.date.to_s] ||= []) << t }
          h
        end

        def compute_length_range(track_by_date)
          max = 0.0
          track_by_date.each_value { |v| max = [max, v.sum(&:length)].max }
          max
        end

        def compute_grid(n, size)
          return nil if n <= 0
          best = nil
          best_diff = Float::INFINITY
          (1..n).each do |cx|
            cy = (n.to_f / cx).ceil
            next if cy <= 0
            cell_w = size[0] / cx
            cell_h = size[1] / cy
            diff = (cell_w - cell_h).abs
            break if cell_w <= 0 || cell_h <= 0
            if diff < best_diff
              best = [cx, cy]
              best_diff = diff
            end
          end
          best
        end

        def interpolate_color(...)
          super
        end
      end
    end
  end
end

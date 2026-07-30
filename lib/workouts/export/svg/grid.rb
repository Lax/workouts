module Workouts
  module Export
    module SVG
      class GridDrawer < BaseDrawer
        def draw(doc, size, offset)
          return "" unless poster.tracks&.any?

          lines = []
          tracks = poster.tracks.reverse.reject(&:skip?)
          n = tracks.size

          sizes, counts = compute_grid(n, size)
          return "" unless sizes && counts

          cell = sizes[0]
          count_x, count_y = counts
          spacing_x = (count_x <= 1) ? 0 : (size[0] - cell * count_x) / (count_x - 1)
          spacing_y = (count_y <= 1) ? 0 : (size[1] - cell * count_y) / (count_y - 1)

          off_x = offset[0] + (size[0] - count_x * cell - (count_x - 1) * spacing_x) / 2
          off_y = offset[1] + (size[1] - count_y * cell - (count_y - 1) * spacing_y) / 2

          tracks.each_with_index do |tr, idx|
            px = off_x + (idx % count_x) * (cell + spacing_x)
            py = off_y + (idx / count_x) * (cell + spacing_y)
            lines << draw_track(tr, cell * 0.9, [px + cell * 0.05, py + cell * 0.05])
          end

          lines.join("\n")
        end

        private

        def draw_track(tr, cell_size, offset)
          polylines = tr.polylines
          return "" if polylines.empty?

          bbox = {
            min_lat: polylines[0].map(&:first).min,
            max_lat: polylines[0].map(&:first).max,
            min_lng: polylines[0].map(&:last).min,
            max_lng: polylines[0].map(&:last).max
          }

          dist_km = poster.m2u(tr.length)
          sd1 = poster.special_distance[:special_distance]
          sd2 = poster.special_distance[:special_distance2]
          color = if dist_km >= sd2
            poster.colors[:special2] || poster.colors[:special]
          elsif sd1 < dist_km && dist_km < sd2
            poster.colors[:special]
          else
            poster.colors[:track]
          end

          title = "#{tr.date} #{format("%.1f", dist_km)}#{poster.u}"
          is_indoor = tr.subtype == "indoor"

          line_group = polylines.flat_map { |polyline| project(polyline, cell_size, offset, bbox) }
          return "" if line_group.empty?

          pts = line_group.map { |p| "#{p[0]},#{p[1]}" }.join(" ")
          dash = is_indoor ? ' stroke-dasharray="1,0.5"' : ""
          poly = %(<polyline points="#{pts}" stroke="#{color}" fill="none" stroke-width="0.5" stroke-linejoin="round" stroke-linecap="round"#{dash} opacity="#{is_indoor ? 0.5 : 1}" />)
          %(<g><title>#{escape(title)}</title>#{poly}</g>)
        end

        def compute_grid(n, size)
          return nil if n == 0 || size[0] <= 0 || size[1] <= 0

          best = nil
          best_diff = Float::INFINITY

          (1..n).each do |cx|
            cy = (n.to_f / cx).ceil
            next if cy <= 0

            cell_w = size[0] / cx
            cell_h = size[1] / cy
            cell = [cell_w, cell_h].min
            diff = (cell_w - cell_h).abs
            if cell > 0 && diff < best_diff
              best = [cell, cx, cy]
              best_diff = diff
            end
          end

          best ? [[best[0], best[0]], [best[1], best[2]]] : nil
        end

        def project(polyline, cell_size, offset, bbox)
          return [] if polyline.empty?

          range_lat = bbox[:max_lat] - bbox[:min_lat]
          range_lng = bbox[:max_lng] - bbox[:min_lng]
          range_lat = 0.001 if range_lat.zero?
          range_lng = 0.001 if range_lng.zero?

          polyline.map do |lat, lng|
            x = offset[0] + ((lng - bbox[:min_lng]) / range_lng) * cell_size
            y = offset[1] + ((bbox[:max_lat] - lat) / range_lat) * cell_size
            [x, y]
          end
        end

        def format(...)
          Kernel.format(...)
        end
      end
    end
  end
end

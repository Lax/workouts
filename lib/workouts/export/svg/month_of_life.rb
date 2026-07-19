module Workouts
  module Export
    module SVG
      class MonthOfLifeDrawer < BaseDrawer
        TOTAL_MONTHS = 1200

        def initialize(poster, birth)
          super(poster)
          raise ArgumentError, "Birth date (--birth YYYY-MM) is required" unless birth

          parts = birth.split("-")
          @birth_year = parts[0].to_i
          @birth_month = parts[1].to_i
          raise ArgumentError, "Invalid birth month" unless (1..12).include?(@birth_month)
        end

        def draw(doc, size, offset)
          return "" unless poster.tracks&.any?

          lines = []
          tracks = poster.tracks.reject(&:skip?)
          distance_by_month = compute_monthly_distances(tracks)

          cols = [1, (size[0] / size[1] * Math.sqrt(TOTAL_MONTHS)).ceil].max
          rows = (TOTAL_MONTHS.to_f / cols).ceil
          spacing_x = size[0].to_f / cols
          spacing_y = size[1].to_f / rows
          radius = [spacing_x, spacing_y].min / 2 * 0.85

          max_dist = distance_by_month.values.max || 1

          now = Time.now
          (0...TOTAL_MONTHS).each do |idx|
            y = @birth_year + (@birth_month - 1 + idx) / 12
            m = (@birth_month - 1 + idx) % 12 + 1
            key = "#{y}-#{m}"

            cx = offset[0] + spacing_x * (idx % cols) + spacing_x / 2
            cy = offset[1] + spacing_y * (idx / cols) + spacing_y / 2

            month_date = Time.new(y, m, 1)
            is_past = month_date < now
            dist = distance_by_month[key] || 0.0

            color = if dist > 0
                      dist_km = poster.m2u(dist)
                      sd1 = poster.special_distance[:special_distance]
                      sd2 = poster.special_distance[:special_distance2]
                      if dist_km >= sd2
                        poster.colors[:special2] || poster.colors[:special]
                      elsif sd1 < dist_km && dist_km < sd2
                        poster.colors[:special]
                      else
                        t = [dist / max_dist, 1.0].min
                        base = is_past ? poster.colors[:dim_past] : poster.colors[:empty_cell]
                        interpolate_color(base, poster.colors[:track], t)
                      end
                    else
                      is_past ? poster.colors[:dim_past] : poster.colors[:empty_cell]
                    end

            age = y - @birth_year + (m - @birth_month) / 12.0
            title = "#{key} (#{age.to_i} years old)"
            title += " #{format('%.1f', poster.m2u(dist))} #{poster.u}" if dist > 0

            lines << %(<g><title>#{escape(title)}</title><circle cx="#{cx}" cy="#{cy}" r="#{radius}" fill="#{color}" /></g>)
          end

          lines.join("\n")
        end

        private

        def compute_monthly_distances(tracks = nil)
          h = Hash.new(0.0)
          (tracks || poster.tracks).each do |t|
            key = "#{t.year}-#{t.date.month}"
            h[key] += t.length
          end
          h
        end

        def interpolate_color(...)
          super
        end
      end
    end
  end
end

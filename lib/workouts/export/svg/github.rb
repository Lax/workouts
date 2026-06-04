module Workouts
  module Export
    module SVG
      class GithubDrawer < BaseDrawer
        def draw(doc, size, offset)
          return "" unless poster.tracks&.any?

          lines = []
          track_by_date = group_by_date
          length_range_by_date = compute_length_range(track_by_date)

          total_by_year = total_length_by_year
          month_names = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]

          years = poster.tracks.map(&:year).uniq.sort.reverse
          cur_offset_y = offset[1]

          years.each do |year|
            year_len = total_by_year[year] || 0
            next if year_len.zero?

            first_day = Date.new(year, 1, 1)
            first_wday = first_day.wday

            is_monday = poster.github_style == "align-monday"
            github_day = is_monday ? first_day - first_wday : first_day
            first_dow = is_monday ? 0 : first_wday

            year_size = 200 * 4.0 / 80.0
            year_style = "font-size:#{year_size}px; font-family:Arial;"
            yl_style = "font-size:#{110 * 3.0 / 80.0}px; font-family:Arial;"
            mn_style = "font-size:2.5px; font-family:Arial"

            lines << tag("text", { x: offset[0], y: cur_offset_y, fill: poster.colors[:text], "dominant-baseline" => "hanging", style: year_style }, year.to_s)
            lines << tag("text", { x: offset[0] + 165, y: cur_offset_y + 5, fill: poster.colors[:text], "dominant-baseline" => "hanging", style: yl_style }, "#{format("%.1f", poster.m2u(year_len))} #{poster.u}")

            month_names.each_with_index do |name, i|
              lines << tag("text", { x: offset[0] + 15.5 * i, y: cur_offset_y + 14, fill: poster.colors[:text], style: mn_style }, name)
            end

            rect_x = offset[0] + 10.0
            dom = [2.6, 2.6]

            (0..53).each do |week|
              if week == 0
                rect_y = cur_offset_y + year_size + 2 + 3.5 * first_dow
                dow = first_dow
              else
                dow = 0
                rect_y = cur_offset_y + year_size + 2
              end

              (dow...7).each do |_|
                break if github_day.year > year

                rect_y += 3.5
                date_key = github_day.to_s
                track_list = track_by_date[date_key]

                if track_list
                  total_len = track_list.sum(&:length)
                  dist_km = poster.m2u(total_len)
                  sd1 = poster.special_distance[:special_distance]
                  sd2 = poster.special_distance[:special_distance2]

                  color = if dist_km >= sd2
                            poster.colors[:special2] || poster.colors[:special]
                          elsif sd1 < dist_km && dist_km < sd2
                            poster.colors[:special]
                          else
                            intensity = length_range_by_date.zero? ? 0 : [total_len / length_range_by_date.to_f, 1.0].min
                            interpolate_color("#444444", poster.colors[:track], intensity)
                          end

                  title = "#{date_key} #{format("%.1f", dist_km)} #{poster.u}"
                else
                  color = "#444444"
                  title = date_key
                end

                rect = tag("rect", { x: rect_x, y: rect_y, width: dom[0], height: dom[1], fill: color })
                lines << %(<g><title>#{escape(title)}</title>#{rect}</g>)
                github_day += 1
              end
              rect_x += 3.5
            end

            cur_offset_y += 3.5 * 9 + year_size + 1.0
          end

          lines.join("\n")
        end

        private

        def group_by_date
          h = {}
          poster.tracks.each do |t|
            key = t.date.to_s
            (h[key] ||= []) << t
          end
          h
        end

        def compute_length_range(track_by_date)
          max = 0.0
          track_by_date.each_value do |tracks|
            len = tracks.sum(&:length)
            max = len if len > max
          end
          max
        end

        def total_length_by_year
          h = Hash.new(0.0)
          poster.tracks.each { |t| h[t.year] += t.length }
          h
        end

        def format(...)
          Kernel.format(...)
        end
      end
    end
  end
end

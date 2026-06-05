module Workouts
  module Export
    module SVG
      class GithubDrawer < BaseDrawer
        REFERENCE = Poster::REFERENCE_DISTANCES

        def draw(doc, size, offset)
          return "" unless poster.tracks&.any?

          lines = []
          track_by_date = group_by_date_and_category
          poster.per_category_max = compute_per_category_max(track_by_date)

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
                tracks_by_cat = track_by_date[date_key]

                if tracks_by_cat
                  dom_cat, dom_len = dominant_category(tracks_by_cat)
                  base_color = poster.color_by_category[dom_cat] || poster.colors[:track]
                  cat_max = poster.per_category_max[dom_cat] || dom_len
                  if cat_max > 0
                    intensity = (dom_len / cat_max.to_f) ** 0.3
                    intensity = [[intensity, 0.0].max, 1.0].min
                  else
                    intensity = 0
                  end
                  color = interpolate_color("#444444", base_color, intensity)
                  css_class = "s-#{dom_cat}"
                  title = build_day_title(date_key, tracks_by_cat)
                else
                  color = "#444444"
                  css_class = nil
                  title = date_key
                end

                rect = tag("rect", { x: rect_x, y: rect_y, width: dom[0], height: dom[1], fill: color })
                if css_class
                  lines << %(<g class="#{css_class}"><title>#{escape(title)}</title>#{rect}</g>)
                else
                  lines << %(<g><title>#{escape(title)}</title>#{rect}</g>)
                end
                github_day += 1
              end
              rect_x += 3.5
            end

            cur_offset_y += 3.5 * 9 + year_size + 1.0
          end

          lines.join("\n")
        end

        private

        # Dominant selection uses raw ratio (d / REF).
        # Any monotonic transform would yield the same winner — no transform needed.
        def dominant_category(tracks_by_cat)
          best_cat = nil
          best_val = -1.0
          tracks_by_cat.each do |cat, tracks|
            total_m = tracks.sum(&:length)
            ref = REFERENCE[cat]
            next unless ref && ref > 0
            val = total_m / ref.to_f
            if val > best_val
              best_val = val
              best_cat = cat
            end
          end
          best_cat ||= tracks_by_cat.keys.first
          total_m = tracks_by_cat[best_cat].sum(&:length)
          [best_cat, total_m]
        end

        def group_by_date_and_category
          h = {}
          poster.tracks.each do |t|
            date_key = t.date.to_date.to_s
            cat = t.sport_category
            h[date_key] ||= {}
            (h[date_key][cat] ||= []) << t
          end
          h
        end

        # Intensity transform: power^0.3
        # Compared options for the skewed per-category distance distribution:
        #   linear  — 82% of color scale wasted on tail outliers
        #   log     — compresses low-end worse than power
        #   CDF     — best visual distribution but unstable as data grows
        # Power^0.3 is a pragmatic balance: simple, stable, good-enough low-end spread.
        def compute_per_category_max(track_by_date)
          maxes = Hash.new(0.0)
          track_by_date.each_value do |cats|
            cats.each do |cat, tracks|
              len = tracks.sum(&:length)
              maxes[cat] = len if len > maxes[cat]
            end
          end
          maxes
        end

        def build_day_title(date_key, tracks_by_cat)
          all = tracks_by_cat.values.flatten
          if all.size == 1
            t = all.first
            "#{date_key}  #{t.sport_category}  #{format_dist(t.length)}  #{format_time(t.moving_time)}"
          else
            lines = [date_key]
            all.each do |t|
              lines << "  #{t.sport_category}  #{format_dist(t.length)}  #{format_time(t.moving_time)}"
            end
            lines.join("&#10;")
          end
        end

        def format_dist(meters)
          "#{format("%.1f", poster.m2u(meters))} #{poster.u}"
        end

        def format_time(seconds)
          return "" unless seconds && seconds > 0
          mins = (seconds / 60).to_i
          if mins >= 60
            "#{mins / 60}h #{format('%02d', mins % 60)}min"
          else
            "#{mins}min"
          end
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

module Workouts
  module Analysis
    class Calculator
      def initialize(db:, activity_filter: nil)
        @db = db
        @activity_filter = activity_filter
      end

      def call
        ds = @db[:activities]
        ds = ds.where(sport_category: @activity_filter) if @activity_filter

        all = ds.all
        return empty_stats if all.empty?

        {
          summary: compute_summary(all),
          monthly: compute_monthly(all),
          yearly: compute_yearly(all),
          streaks: compute_streaks(all),
          activity_types: distinct_categories(all)
        }
      end

      private

      def empty_stats
        {summary: {}, monthly: [], yearly: [], streaks: {}, activity_types: []}
      end

      def compute_summary(rows)
        total_dist = 0.0
        total_time = 0
        total_elev = 0.0
        breakdown = Hash.new { |h, k| h[k] = {count: 0, distance_km: 0.0, moving_time_h: 0.0} }

        rows.each do |r|
          cat = r[:sport_category] || "other"
          d = r[:distance] || 0
          t = r[:moving_time] || 0
          e = r[:elevation_gain] || 0

          total_dist += d
          total_time += t
          total_elev += e

          breakdown[cat][:count] += 1
          breakdown[cat][:distance_km] += d / 1000.0
          breakdown[cat][:moving_time_h] += t / 3600.0
        end

        cadences = rows.map { |r| r[:average_cadence] }.compact
        powers = rows.map { |r| r[:average_power] }.compact

        grouped_run_ids = if @db.table_exists?(:dedup_group_members)
          @db[:dedup_group_members].select_map(:run_id)
        else
          []
        end
        unique = rows.reject { |a| grouped_run_ids.include?(a[:run_id]) }
        unique_count = unique.size + (@db.table_exists?(:dedup_groups) ? @db[:dedup_groups].count : 0)

        {
          total_activities: rows.size,
          unique_activities: unique_count,
          total_distance_km: total_dist / 1000.0,
          total_moving_time_h: total_time / 3600.0,
          total_elevation_gain_m: total_elev,
          avg_cadence: cadences.any? ? (cadences.sum / cadences.size).round(1) : nil,
          avg_power: powers.any? ? (powers.sum / powers.size).round(1) : nil,
          sport_breakdown: breakdown.sort_by { |_, v| -v[:count] }.map { |cat, v|
            {category: cat, count: v[:count], distance_km: v[:distance_km].round(1),
             moving_time_h: v[:moving_time_h].round(1)}
          }
        }
      end

      def compute_monthly(rows)
        monthly = Hash.new { |h, k|
          h[k] = {count: 0, distance_km: 0.0, moving_time_h: 0.0,
                                   total_hr: 0.0, hr_count: 0, total_elev: 0.0,
                                   total_cadence: 0.0, cadence_count: 0,
                                   total_power: 0.0, power_count: 0}
        }

        rows.each do |r|
          next unless r[:start_date_local] || r[:start_date]

          ym = (r[:start_date_local] || r[:start_date])[0..6]
          d = r[:distance] || 0
          t = r[:moving_time] || 0
          hr = r[:average_heartrate]
          e = r[:elevation_gain] || 0

          monthly[ym][:count] += 1
          monthly[ym][:distance_km] += d / 1000.0
          monthly[ym][:moving_time_h] += t / 3600.0
          monthly[ym][:total_elev] += e
          if hr && hr > 0
            monthly[ym][:total_hr] += hr
            monthly[ym][:hr_count] += 1
          end
          cad = r[:average_cadence]
          pow = r[:average_power]
          if cad && cad > 0
            monthly[ym][:total_cadence] += cad
            monthly[ym][:cadence_count] += 1
          end
          if pow && pow > 0
            monthly[ym][:total_power] += pow
            monthly[ym][:power_count] += 1
          end
        end

        monthly.sort.map { |ym, v|
          pace = (v[:moving_time_h] > 0 && v[:distance_km] > 0) ?
            format_pace(v[:moving_time_h] * 3600 / v[:distance_km]) : nil
          {
            year: ym[0..3].to_i,
            month: ym[5..6].to_i,
            count: v[:count],
            distance_km: v[:distance_km].round(1),
            moving_time_h: v[:moving_time_h].round(1),
            avg_pace: pace,
            avg_hr: (v[:hr_count] > 0) ? (v[:total_hr] / v[:hr_count]).round(0) : nil,
            avg_cadence: (v[:cadence_count] > 0) ? (v[:total_cadence] / v[:cadence_count]).round(0) : nil,
            avg_power: (v[:power_count] > 0) ? (v[:total_power] / v[:power_count]).round(0) : nil,
            elevation_gain_m: v[:total_elev].round(0)
          }
        }
      end

      def compute_yearly(rows)
        by_year = Hash.new { |h, k| h[k] = [] }
        rows.each do |r|
          next unless r[:start_date_local] || r[:start_date]
          by_year[(r[:start_date_local] || r[:start_date])[0..3].to_i] << r
        end

        by_year.sort.map { |year, acts|
          total_dist = acts.sum { |r| r[:distance] || 0 } / 1000.0
          total_time = acts.sum { |r| r[:moving_time] || 0 }
          longest = acts.map { |r| r[:distance] || 0 }.max / 1000.0

          streak = calculate_streak(acts)

          {year: year, count: acts.size, distance_km: total_dist.round(1),
           moving_time_h: (total_time / 3600.0).round(1),
           longest_km: longest.round(1), streak: streak}
        }
      end

      def compute_streaks(rows)
        dates = rows.filter_map { |r|
          next nil unless r[:start_date_local] || r[:start_date]
          begin
            Date.parse(r[:start_date_local] || r[:start_date])
          rescue
            nil
          end
        }.uniq.sort

        return {current: 0, all_time: 0, year_max: {}} if dates.empty?

        max_streak = 1
        current_streak = 1

        (1...dates.length).each do |i|
          if (dates[i] - dates[i - 1]).to_i == 1
            current_streak += 1
            max_streak = current_streak if current_streak > max_streak
          else
            current_streak = 1
          end
        end

        today = Date.today
        current = if dates.last == today || dates.last == today - 1
          streak = 1
          j = dates.length - 2
          while j >= 0 && (dates[j + 1] - dates[j]).to_i == 1
            streak += 1
            j -= 1
          end
          streak
        else
          0
        end

        {current: current, all_time: max_streak}
      end

      def distinct_categories(rows)
        rows.map { |r| r[:sport_category] }.uniq.compact.sort
      end

      def format_pace(sec_per_km)
        min = (sec_per_km / 60).to_i
        sec = sec_per_km.to_i % 60
        "#{min}'#{format("%02d", sec)}\""
      end

      def calculate_streak(rows)
        dates = rows.filter_map { |r|
          next nil unless r[:start_date_local] || r[:start_date]
          begin
            Date.parse(r[:start_date_local] || r[:start_date])
          rescue
            nil
          end
        }.uniq.sort
        return 0 if dates.empty?

        max_s = 1
        cur = 1
        (1...dates.length).each do |i|
          if (dates[i] - dates[i - 1]).to_i == 1
            cur += 1
            max_s = cur if cur > max_s
          else
            cur = 1
          end
        end
        max_s
      end
    end
  end
end

module Workouts
  module Export
    module SVG
      class Track
        attr_reader :date, :year, :length, :effective_length, :polyline,
                    :sport_category, :sport_type, :moving_time, :duplicate_info,
                    :average_cadence, :average_power, :max_heartrate

        def initialize(activity, colors, special_distance)
          @date = Time.parse(activity[:start_date]) rescue Time.now
          @year = @date.year
          @length = activity[:distance] || 0
          @polyline = activity[:summary_polyline]
          @sport_category = activity[:sport_category] || "other"
          @sport_type = activity[:sport_type]
          @moving_time = activity[:moving_time] || 0
          @run_id = activity[:run_id]
          @colors = colors
          @special_distance = special_distance
          @duplicate_info = activity[:duplicate_info] ? ::JSON.parse(activity[:duplicate_info]) : []
          @average_cadence = activity[:average_cadence]
          @average_power   = activity[:average_power]
          @max_heartrate   = activity[:max_heartrate]
          @effective_length = compute_effective_length
        end

        def skip?
          @duplicate_info.any? { |d| d["flag"] == "derived" }
        end

        def conflict?
          @duplicate_info.any? { |d| d["flag"] == "overlap" }
        end

        def duplicate_source
          info = @duplicate_info.first
          info ? "#{info["source"]} #{info["run_id"]}" : nil
        end

        def special
          dist_km = @length * 0.001
          sd1 = @special_distance[:special_distance]
          sd2 = @special_distance[:special_distance2]
          dist_km > sd1 && dist_km < sd2
        end

        def subtype
          @sport_type
        end

        def polylines
          return [] unless @polyline
          points = Geo::Polyline.decode(@polyline)
          return [] if points.nil? || points.empty?
          [points.map { |lat, lng| [lng, lat] }]
        end

        def bbox
          return nil unless @polyline
          points = Geo::Polyline.decode(@polyline)
          return nil if points.nil? || points.empty?
          lats = points.map(&:first)
          lngs = points.map(&:last)
          { min_lat: lats.min, max_lat: lats.max, min_lng: lngs.min, max_lng: lngs.max }
        end

        def start_time_local
          @date
        end

        private

        def compute_effective_length
          return @length if @duplicate_info.empty?
          @duplicate_info.each do |d|
            pd = d["primary_distance"]
            next unless pd
            if d["flag"] == "derived"
              return 0.0
            elsif d["flag"] == "overlap"
              excess = @length - pd
              return excess > 0 ? excess : 0.0
            end
          end
          @length
        end
      end
    end
  end
end

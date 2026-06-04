module Workouts
  module Export
    module SVG
      class Track
        attr_reader :date, :year, :length, :polyline, :sport_category, :sport_type, :moving_time

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
      end
    end
  end
end

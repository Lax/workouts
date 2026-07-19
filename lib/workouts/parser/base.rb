require "time"

module Workouts
  module Parser
    class Base
      def initialize(source: nil)
        @source_name = source
      end

      def call(_input)
        raise NotImplementedError
      end

      private

      def haversine(p1, p2)
        lat1 = deg_to_rad(p1[0])
        lat2 = deg_to_rad(p2[0])
        dlat = deg_to_rad(p2[0] - p1[0])
        dlon = deg_to_rad(p2[1] - p1[1])

        a = Math.sin(dlat / 2) ** 2 +
            Math.cos(lat1) * Math.cos(lat2) *
            Math.sin(dlon / 2) ** 2
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        6371000.0 * c
      end

      def deg_to_rad(deg)
        deg * Math::PI / 180.0
      end

      def total_distance(points)
        return 0.0 if points.length < 2
        (1...points.length).sum { |i| haversine(points[i - 1], points[i]) }
      end

      def elevation_gain(points)
        return 0.0 if points.length < 2
        (1...points.length).sum do |i|
          elev1 = points[i - 1][2] || 0.0
          elev2 = points[i][2] || 0.0
          gain = elev2 - elev1
          gain > 0 ? gain : 0.0
        end
      end

      def moving_time_from_points(points, threshold_s: 30)
        return 0 if points.length < 2

        total = 0
        (1...points.length).each do |i|
          t1 = points[i - 1][3]
          t2 = points[i][3]
          next unless t1 && t2

          diff = (t2 - t1).abs
          total += diff if diff <= threshold_s
        end
        total.round
      end

      def elapsed_time_from_points(points)
        return 0 if points.length < 2
        times = points.map { |p| p[3] }.compact
        return 0 if times.length < 2
        ((times.last - times.first).abs).round
      end

      def build_run_id(source_prefix, value)
        "#{source_prefix}_#{value}"
      end

      def default_sport
        "other"
      end

      def simplify_polyline(points, max_points: 500)
        return Geo::Polyline.encode(points) if points.length <= max_points

        step = (points.length.to_f / max_points).ceil
        sampled = (0...points.length).step(step).map { |i| points[i] }
        sampled << points.last if sampled.last != points.last
        Geo::Polyline.encode(sampled)
      end

      def normalize_sport_type(type)
        return default_sport if type.nil? || type.empty?

        mapping = {
          "running" => "run",
          "run" => "run",
          "cycling" => "ride",
          "biking" => "ride",
          "ride" => "ride",
          "hiking" => "hike",
          "hike" => "hike",
          "walking" => "walk",
          "walk" => "walk",
          "swimming" => "swim",
          "swim" => "swim",
          "skiing" => "ski",
          "ski" => "ski",
          "workout" => "workout",
          "other" => "other"
        }
        mapping[type.downcase.strip] || default_sport
      end

      def build_activity_attrs(data)
        {
          run_id: data[:run_id],
          name: data[:name],
          distance: data[:distance]&.round(2),
          moving_time: data[:moving_time]&.round,
          elapsed_time: data[:elapsed_time]&.round,
          sport_category: data[:sport_category] || default_sport,
          sport_type: data[:sport_type],
          start_date: format_time(data[:start_date]),
          start_date_local: format_time(data[:start_date_local]),
          location_country: data[:location_country],
          summary_polyline: data[:summary_polyline],
          average_heartrate: data[:average_heartrate]&.round(1),
          average_speed: data[:distance] && data[:moving_time].to_f.positive? ? (data[:distance].to_f / data[:moving_time]).round(2) : data[:average_speed],
          elevation_gain: data[:elevation_gain]&.round(1),
          source: @source_name || data[:source]
        }
      end

      def format_time(t)
        return nil unless t
        t.respond_to?(:iso8601) ? t.utc.iso8601 : t.to_s
      end
    end
  end
end

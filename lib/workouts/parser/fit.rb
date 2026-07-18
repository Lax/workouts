require "json"
require "securerandom"
require "time"

module Workouts
  module Parser
    class FIT < Base
      FIT_EPOCH = Time.utc(1989, 12, 31).freeze

      def call(input)
        path = input.is_a?(String) ? input : nil
        return [] unless path && File.exist?(path)

        records = Workouts::FIT::Decoder.decode(path)
        return [] if records.empty?

        points = records.filter_map { |r| record_to_point(r) }
        return [] if points.empty?

        times = points.map { |p| p[3] }.compact
        start_date = times.min
        end_date = times.max

        sport_type = Workouts::FIT::Decoder.sport(path)

        [build_activity_attrs({
          run_id: build_run_id("fit", SecureRandom.hex(8)),
          name: nil,
          distance: total_distance(points),
          moving_time: moving_time_from_points(points),
          elapsed_time: elapsed_time_from_points(points),
          sport_category: normalize_sport_type(sport_type),
          sport_type: sport_type,
          start_date: start_date,
          start_date_local: start_date,
          location_country: nil,
          summary_polyline: simplify_polyline(points.map { |p| [p[0], p[1]] }),
          average_heartrate: average_heartrate(points),
          elevation_gain: elevation_gain(points),
          source: "fit"
        })]
      end

      private

      def record_to_point(rec)
        lat = rec["positionLat"]
        lon = rec["positionLong"]
        return nil unless lat && lon

        ts = rec["timestamp"]
        time = ts.is_a?(Numeric) ? FIT_EPOCH + ts : parse_time(ts)

        [lat, lon, rec["altitude"], time, rec["heartRate"]]
      end

      def average_heartrate(points)
        hrs = points.map { |p| p[4] }.compact
        return nil if hrs.empty?
        hrs.sum / hrs.size
      end

      def parse_time(str)
        return nil unless str
        Time.parse(str.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end

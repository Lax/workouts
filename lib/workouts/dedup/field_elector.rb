# frozen_string_literal: true

require "time"

module Workouts
  module Dedup
    class FieldElector
      FIELD_ELECTION_RULES = {
        distance: :median,
        moving_time: :min,
        elapsed_time: :max,
        average_heartrate: :mean,
        max_heartrate: :max,
        average_power: :non_null,
        max_power: :non_null,
        average_cadence: :non_null,
        max_cadence: :non_null,
        summary_polyline: :best_polyline,
        elevation_gain: :median,
        calories: :median,
        average_temperature: :non_null,
        average_speed: :computed,
        name: :best_name,
        start_date: :earliest
      }.freeze

      SOURCE_NAME_PRIORITY = {
        garmin: 1, strava: 2, igpsport: 3, xoss: 4,
        keep: 5, xingzhe: 6, apple_health: 7
      }.freeze

      def elect(field, values, sources = [])
        rule = FIELD_ELECTION_RULES[field]
        non_nil = values.compact
        return nil if non_nil.empty?

        case rule
        when :median
          sorted = non_nil.sort
          sorted[sorted.size / 2]
        when :mean
          non_nil.sum / non_nil.size
        when :min
          non_nil.min
        when :max
          non_nil.max
        when :non_null
          non_nil.first
        when :best_polyline
          candidates = non_nil.select { |v| v.is_a?(String) && !v.empty? }
          return nil if candidates.empty?
          candidates.max_by { |v| decode_polyline_size(v) }
        when :computed
          nil
        when :best_name
          best_name(values, sources)
        when :earliest
          non_nil.min_by { |v|
            begin
              Time.parse(v.to_s)
            rescue
              Time.at(0)
            end
          }
        else
          non_nil.first
        end
      end

      private

      def decode_polyline_size(polyline)
        return 0 unless polyline.is_a?(String) && !polyline.empty?
        polyline.size / 3
      end

      def best_name(values, sources)
        pairs = values.zip(sources)
        pairs.min_by { |_, src| SOURCE_NAME_PRIORITY[src&.to_sym] || 99 }&.first
      end
    end
  end
end

module Workouts
  module DB
    class Activity < Sequel::Model(:activities)
      unrestrict_primary_key

      SPORT_CATEGORIES = %w[run ride hike walk swim ski workout other].freeze

      def to_export_hash
        {
          run_id: run_id,
          name: name,
          distance: distance,
          moving_time: format_time(moving_time),
          type: sport_category,
          subtype: sport_type,
          start_date: start_date,
          start_date_local: start_date_local,
          location_country: location_country,
          summary_polyline: summary_polyline,
          average_heartrate: average_heartrate,
          average_speed: average_speed,
          elevation_gain: elevation_gain
        }
      end

      private

      def format_time(seconds)
        return nil unless seconds
        hours = seconds / 3600
        minutes = (seconds % 3600) / 60
        secs = seconds % 60
        format("%d:%02d:%02d", hours, minutes, secs)
      end
    end
  end
end

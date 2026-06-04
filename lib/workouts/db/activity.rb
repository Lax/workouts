module Workouts
  module DB
    SPORT_CATEGORIES = %w[run ride hike walk swim ski workout other].freeze

    def self.activity_to_hash(a)
      return nil unless a

      {
        run_id: a[:run_id],
        name: a[:name],
        distance: a[:distance],
        moving_time: format_time(a[:moving_time]),
        type: a[:sport_category],
        subtype: a[:sport_type],
        start_date: a[:start_date],
        start_date_local: a[:start_date_local],
        location_country: a[:location_country],
        summary_polyline: a[:summary_polyline],
        average_heartrate: a[:average_heartrate],
        average_speed: a[:average_speed],
        elevation_gain: a[:elevation_gain]
      }
    end

    def self.format_time(seconds)
      return nil unless seconds
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60
      format("%d:%02d:%02d", hours, minutes, secs)
    end
  end
end

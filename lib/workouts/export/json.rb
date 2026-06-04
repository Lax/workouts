require "json"

module Workouts
  module Export
    class JSON
      def initialize(db:, output:, activity_filter: nil)
        @db = db
        @output = output
        @activity_filter = activity_filter
      end

      def call
        dataset = @db[:activities].order(Sequel.desc(:start_date))
        dataset = dataset.where(sport_category: @activity_filter) if @activity_filter

        activities = dataset.all.map { |a| format_activity(a) }
        File.write(@output, ::JSON.pretty_generate(activities))
        activities.size
      end

      private

      def format_activity(a)
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

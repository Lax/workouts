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
        base = {
          run_id: a[:run_id],
          name: a[:name],
          distance: a[:distance],
          moving_time: a[:moving_time],
          type: a[:sport_category],
          sport_type: a[:sport_type],
          start_date: a[:start_date],
          start_date_local: a[:start_date_local],
          location_country: a[:location_country],
          summary_polyline: a[:source] == "keep" && a[:summary_polyline] == Workouts::Sync::Keep::PLACEHOLDER_POLYLINE ?
            nil : a[:summary_polyline],
          average_heartrate: a[:average_heartrate] && a[:average_heartrate] != 0 ? a[:average_heartrate] : nil,
          max_heartrate: a[:max_heartrate],
          average_cadence: a[:average_cadence],
          max_cadence: a[:max_cadence],
          average_power: a[:average_power],
          max_power: a[:max_power],
          calories: a[:calories],
          average_temperature: a[:average_temperature],
          average_speed: a[:average_speed],
          elevation_gain: a[:elevation_gain],
          source: a[:source],
        }
        if a[:divisions]
          base[:divisions] = ::JSON.parse(a[:divisions])
        end
        base
      end


    end
  end
end

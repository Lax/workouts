require "csv"

module Workouts
  module Export
    class CSV
      HEADERS = %w[
        run_id name distance moving_time elapsed_time
        sport_category sport_type start_date start_date_local
        location_country summary_polyline
        average_heartrate average_speed elevation_gain source
      ].freeze

      def initialize(db:, output:, activity_filter: nil)
        @db = db
        @output = output
        @activity_filter = activity_filter
      end

      def call
        dataset = @db[:activities].order(Sequel.desc(:start_date))
        dataset = dataset.where(sport_category: @activity_filter) if @activity_filter

        ::CSV.open(@output, "w") do |csv|
          csv << HEADERS
          dataset.each { |a| csv << HEADERS.map { |h| a[h.to_sym] } }
        end
      end
    end
  end
end

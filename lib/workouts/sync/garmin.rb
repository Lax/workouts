require_relative "base"

module Workouts
  module Sync
    class Garmin < Base
      BASE_URL = "https://connect.garmin.com"

      def call
        return 0 if @config.empty?
        0
      end
    end
  end
end

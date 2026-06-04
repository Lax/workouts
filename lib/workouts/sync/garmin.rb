require_relative "garmin_base"

module Workouts
  module Sync
    class Garmin < GarminBase
      def initialize(...)
        super
        @domain = "garmin.com"
      end
    end
  end
end

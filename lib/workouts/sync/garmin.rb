require_relative "garmin_base_di"

module Workouts
  module Sync
    class Garmin < GarminBaseDI
      def initialize(...)
        super
        @domain = "garmin.com"
      end
    end
  end
end

require_relative "garmin_base"

module Workouts
  module Sync
    class GarminCN < GarminBase
      def initialize(...)
        super
        @domain = "garmin.cn"
      end
    end
  end
end

require_relative "base"

module Workouts
  module Sync
    class GarminCN < Base
      BASE_URL = "https://connect.garmin.cn"

      def call
        return 0 if @config.empty?
        0
      end
    end
  end
end

require_relative "garmin_base"

module Workouts
  module Sync
    class GarminCN < GarminBase
      def initialize(...)
        super
        @domain = "garmin.cn"
        @ssl_verify = @config.key?("ssl_verify") ? @config["ssl_verify"] : false
      end
    end
  end
end

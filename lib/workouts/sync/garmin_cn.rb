require_relative "garmin_base"

module Workouts
  module Sync
    class GarminCN < GarminBase
      def initialize(...)
        super
        @domain = "garmin.cn"
        @ssl_verify = @config.key?("ssl_verify") ? @config["ssl_verify"] : false
      end

      def raw_dir
        File.join("data", "raw", "garmin_cn")
      end

      def std_dir
        File.join("data", "std", "garmin_cn")
      end

      def source_prefix
        "garmin_cn"
      end
    end
  end
end

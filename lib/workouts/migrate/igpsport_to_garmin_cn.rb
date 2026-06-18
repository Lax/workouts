require_relative "igpsport_to_garmin"

module Workouts
  module Migrate
    class IGPSportToGarminCN < IGPSportToGarmin
      private

      def authenticate
        result = Auth::GarminToken.for_cn(@config)
        return false unless result

        @access_token = result[:access_token]
        @domain = result[:domain]
        true
      end

      def upload_map_dir
        File.join("data", "migrate", "igpsport_to_garmin_cn")
      end
    end
  end
end

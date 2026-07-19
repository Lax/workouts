require "timezone_finder"

module Workouts
  module Timezone
    # Resolve IANA timezone string from GPS coordinates.
    # Falls back to config default when GPS is unavailable or lookup fails.
    class Resolver
      def initialize(config, finder: nil)
        default = config.is_a?(Hash) ? config.dig("system", "timezone") : config
        @finder = finder || TimezoneFinder.create
        @default = default || "Asia/Shanghai"
      end

      def resolve(lat, lng)
        return @default unless lat && lng

        tz = @finder.timezone_at(lat: lat.to_f, lng: lng.to_f)
        tz = nil if tz.is_a?(String) && tz.empty?
        tz || @default
      end
    end
  end
end

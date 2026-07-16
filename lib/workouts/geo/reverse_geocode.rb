require_relative "amap_client"
require_relative "nominatim_client"

module Workouts
  module Geo
    class ReverseGeocode
      CHINA_BBOX = {
        min_lng: 73, max_lng: 135,
        min_lat: 18, max_lat: 54,
      }.freeze

      def initialize(amap_key: nil)
        @amap = amap_key ? AMapClient.new(api_key: amap_key) : nil
        @nominatim = NominatimClient.new
      end

      def lookup(lat, lng)
        in_china?(lat, lng) ? lookup_china(lat, lng) : lookup_intl(lat, lng)
      end

      private

      def in_china?(lat, lng)
        lat >= CHINA_BBOX[:min_lat] && lat <= CHINA_BBOX[:max_lat] &&
          lng >= CHINA_BBOX[:min_lng] && lng <= CHINA_BBOX[:max_lng]
      end

      def lookup_china(lat, lng)
        raise "AMap API key not configured" unless @amap
        @amap.reverse_geocode(lat, lng)
      rescue => e
        { province: nil, city: nil, district: nil, township: nil, source: "error", error: e.message }
      end

      def lookup_intl(lat, lng)
        @nominatim.reverse_geocode(lat, lng)
      rescue => e
        { province: nil, city: nil, district: nil, township: nil, source: "error", error: e.message }
      end
    end
  end
end

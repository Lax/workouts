require "net/http"
require "json"
require "uri"

module Workouts
  module Geo
    class AMapClient
      BASE_URL = "https://restapi.amap.com/v3/geocode/regeo".freeze

      def initialize(api_key:)
        @api_key = api_key
        @mutex = Mutex.new
        @last_request = 0.0
        @min_interval = 0.2
      end

      def reverse_geocode(lat, lng)
        rate_limit
        uri = URI(BASE_URL)
        uri.query = URI.encode_www_form(
          key: @api_key,
          location: "#{lng},#{lat}",
          output: "JSON",
          radius: 1000,
          extensions: "all",
        )
        resp = Net::HTTP.get_response(uri)
        body = JSON.parse(resp.body)
        if body["status"] != "1"
          raise "AMap API error: #{body["info"]}"
        end
        parse_response(body)
      end

      private

      def parse_response(body)
        comp = body.dig("regeocode", "addressComponent") || {}
        province = comp["province"].to_s.empty? ? nil : comp["province"]
        city = comp["city"].to_s.empty? || comp["city"] == comp["province"] ? nil : comp["city"]
        district = comp["district"].to_s.empty? ? nil : comp["district"]
        township = comp["township"].to_s.empty? ? nil : comp["township"]
        { province: province, city: city, district: district, township: township, source: "amap" }
      end

      def rate_limit
        @mutex.synchronize do
          elapsed = Time.now.to_f - @last_request
          sleep(@min_interval - elapsed) if elapsed < @min_interval
          @last_request = Time.now.to_f
        end
      end
    end
  end
end

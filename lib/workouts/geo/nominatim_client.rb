require "net/http"
require "json"
require "uri"

module Workouts
  module Geo
    class NominatimClient
      BASE_URL = "https://nominatim.openstreetmap.org/reverse".freeze
      USER_AGENT = "WorkoutsCLI/1.0 (geo-detector)"

      def initialize
        @mutex = Mutex.new
        @last_request = 0.0
        @min_interval = 1.0
      end

      def reverse_geocode(lat, lng)
        rate_limit
        uri = URI(BASE_URL)
        uri.query = URI.encode_www_form(
          lat: lat,
          lon: lng,
          format: "jsonv2",
          addressdetails: 1,
          zoom: 10
        )
        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          req = Net::HTTP::Get.new(uri)
          req["User-Agent"] = USER_AGENT
          http.request(req)
        end
        body = JSON.parse(resp.body)
        if body["error"]
          raise "Nominatim error: #{body["error"]}"
        end
        parse_response(body)
      end

      private

      def parse_response(body)
        addr = body["address"] || {}
        country = addr["country"]
        state = addr["state"]
        {province: country, city: state, district: nil, township: nil, source: "nominatim"}
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

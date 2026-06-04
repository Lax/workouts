require_relative "base"

module Workouts
  module Sync
    class Strava < Base
      BASE_URL = "https://www.strava.com/api/v3"

      def call
        return 0 unless credentials_present?

        access_token = refresh_access_token
        return 0 unless access_token

        page = 1
        count = 0

        loop do
          activities = fetch_activities(access_token, page)
          break if activities.empty?

          activities.each do |act|
            type = map_sport_type(act["type"], act["sport_type"])
            next if skip_type?(type)

            upsert_activity(build_attrs(act, type))
            count += 1
          end

          page += 1
        end

        count
      end

      private

      def credentials_present?
        @config["client_id"].to_s != "" &&
        @config["client_secret"].to_s != "" &&
        @config["refresh_token"].to_s != ""
      end

      def refresh_access_token
        resp = Faraday.post("https://www.strava.com/oauth/token") do |req|
          req.body = {
            client_id: @config["client_id"],
            client_secret: @config["client_secret"],
            refresh_token: @config["refresh_token"],
            grant_type: "refresh_token"
          }
        end

        raise "Strava token refresh failed: #{resp.status}" unless resp.success?
        JSON.parse(resp.body)["access_token"]
      end

      def fetch_activities(token, page)
        resp = Faraday.get("#{BASE_URL}/athlete/activities") do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.params = { page: page, per_page: 100 }
        end

        return [] unless resp.success?
        JSON.parse(resp.body)
      end

      def build_attrs(act, category)
        start_t = Time.parse(act["start_date"]) rescue nil
        local_t = Time.parse(act["start_date_local"]) rescue nil

        {
          run_id: "strava_#{act["id"]}",
          name: act["name"],
          distance: act["distance"],
          moving_time: act["moving_time"],
          elapsed_time: act["elapsed_time"],
          sport_category: category,
          sport_type: (act["sport_type"] || act["type"])&.downcase,
          start_date: start_t&.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: local_t&.strftime("%Y-%m-%d %H:%M:%S"),
          location_country: act["location_country"],
          summary_polyline: act.dig("map", "summary_polyline"),
          average_heartrate: act["average_heartrate"],
          average_speed: act["average_speed"],
          elevation_gain: act["total_elevation_gain"],
          source: "strava"
        }
      end

      def map_sport_type(type, sport_type)
        st = (sport_type || type).to_s.downcase

        case st
        when "run", "trailrun", "trail_run" then "run"
        when "virtualrun", "virtual_run", "indoorrun", "indoor_run" then "run"
        when "ride", "mountainbike", "gravelride", "ebikeride" then "ride"
        when "virtualride", "indoor_ride", "indoorride", "virtual_ride" then "ride"
        when "hike" then "hike"
        when "walk" then "walk"
        when "swim" then "swim"
        when "ski", "backcountryski", "nordicski" then "ski"
        when "workout", "strengthtraining" then "workout"
        else "other"
        end
      end
    end
  end
end

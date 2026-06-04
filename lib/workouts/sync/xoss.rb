require_relative "base"

module Workouts
  module Sync
    class XOSS < Base
      BASE_URL = "https://www.imxingzhe.com"
      LOGIN_URL = "#{BASE_URL}/api/v1/user/login/"
      ACTIVITIES_URL = "#{BASE_URL}/api/activities/"

      SPORT_MAP = {
        1 => "ride",
        2 => "run",
        3 => "walk",
        4 => "swim",
        5 => "hike",
        6 => "ski"
      }.freeze

      def initialize(...)
        super
        @email = @config["email"]
        @password = @config["password"]
      end

      def call
        return 0 if @email.nil? || @password.nil?

        return 0 unless login

        sync_activities
      end

      private

      def login
        resp = Faraday.post(LOGIN_URL,
          JSON.generate({ account: @email, password: @password }),
          { "Content-Type" => "application/json", "Accept" => "application/json" }
        )
        return false unless resp.status == 200

        data = JSON.parse(resp.body)
        return false unless data["code"] == 0

        token = data.dig("data", "token")
        if token
          @headers = {
            "Authorization" => "Token #{token}",
            "Accept" => "application/json"
          }
        else
          @headers = { "Accept" => "application/json" }
          set_cookies(resp)
        end
        true
      end

      def sync_activities
        existing = existing_run_ids
        page = 1
        count = 0

        loop do
          activities = fetch_page(page)
          break if activities.nil? || activities.empty?

          activities.each do |act|
            act_id = act["id"].to_s
            next if existing.include?(act_id)

            count += 1 if process_activity(act, act_id)
          end

          page += 1
        end

        count
      end

      def fetch_page(page)
        resp = Faraday.get(ACTIVITIES_URL,
          { page: page, page_size: 50 },
          @headers
        )
        return nil unless resp.status == 200

        data = JSON.parse(resp.body)
        data["results"] || data["data"] || []
      end

      def process_activity(act, act_id)
        type = map_sport(act["sport_type"] || act["type"])

        start_t = parse_xoss_time(act["start_time"] || act["start_date"] || act["created_at"])
        distance = (act["distance"] || act["total_distance"] || 0).to_f
        moving_time = (act["moving_time"] || act["elapsed_time"] || act["duration"] || 0).to_i
        elapsed_time = (act["elapsed_time"] || act["duration"] || moving_time).to_i

        attrs = {
          run_id: "xoss_#{act_id}",
          name: act["name"] || act["title"] || "XOSS Activity",
          distance: distance,
          moving_time: moving_time,
          elapsed_time: elapsed_time,
          sport_category: type,
          sport_type: act["sport_type"] || act["type"],
          start_date: start_t&.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: start_t&.strftime("%Y-%m-%d %H:%M:%S"),
          location_country: act["location"] || act["city"],
          average_heartrate: (act["avg_hr"] || act["average_heartrate"] || 0).to_f.nonzero?,
          average_speed: (act["avg_speed"] || act["average_speed"] || 0).to_f.nonzero?,
          elevation_gain: (act["total_elevation"] || act["elevation"] || act["elevation_gain"] || 0).to_f.nonzero?,
          source: "xoss"
        }

        upsert_activity(attrs)
        true
      end

      def map_sport(sport)
        return "other" unless sport

        if sport.is_a?(Integer)
          SPORT_MAP[sport] || "other"
        else
          case sport.to_s.downcase
          when /riding|cycling|bike|ride|1/ then "ride"
          when /running|run|2/ then "run"
          when /walking|walk|3/ then "walk"
          when /swimming|swim|4/ then "swim"
          when /hiking|hike|5/ then "hike"
          when /skiing|ski|6/ then "ski"
          when /workout/ then "workout"
          else "other"
          end
        end
      end

      def parse_xoss_time(str)
        return nil unless str
        Time.parse(str.to_s)
      rescue
        nil
      end

      def set_cookies(resp)
        cookie_str = resp.headers["set-cookie"]
        return unless cookie_str
        @headers["Cookie"] = cookie_str.split(";").first
      end

      def existing_run_ids
        @db[:activities].where(source: "xoss").select_map(:run_id)
          .map { |id| id.sub("xoss_", "") }
      end
    end
  end
end

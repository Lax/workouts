require_relative "base"

module Workouts
  module Sync
    class XingZhe < Base
      BASE_URL = "https://www.imxingzhe.com"
      LOGIN_URL = "#{BASE_URL}/api/v1/user/login/"

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

        @token = data.dig("data", "token")
        return false unless @token

        @headers = { "Authorization" => "Token #{@token}", "Accept" => "application/json" }
        true
      end

      def sync_activities
        page = 1
        count = 0

        loop do
          activities = fetch_page(page)
          break if activities.nil? || activities.empty?

          activities.each do |act|
            type = map_sport(act["sport_type"] || act["type"])
            next if skip_type?(type)

            count += 1 if process_activity(act, type)
          end

          page += 1
        end

        count
      end

      def fetch_page(page)
        resp = Faraday.get("#{BASE_URL}/api/activities/",
          { page: page, page_size: 50 },
          @headers
        )
        return nil unless resp.status == 200

        data = JSON.parse(resp.body)
        data["results"] || data["data"] || []
      end

      def process_activity(act, type)
        act_id = act["id"].to_s

        start_t = parse_time(act["start_time"] || act["start_date"] || act["created_at"])
        distance = (act["distance"] || act["total_distance"] || 0).to_f
        moving_time = (act["moving_time"] || act["elapsed_time"] || act["duration"] || 0).to_i
        elapsed_time = (act["elapsed_time"] || act["duration"] || moving_time).to_i

        attrs = {
          run_id: "xingzhe_#{act_id}",
          name: act["name"] || act["title"] || "XingZhe Activity",
          distance: distance,
          moving_time: moving_time > 0 ? moving_time : nil,
          elapsed_time: elapsed_time > 0 ? elapsed_time : nil,
          sport_category: type,
          sport_type: (act["sport_type"] || act["type"]).to_s,
          start_date: start_t,
          start_date_local: start_t,
          location_country: act["location"] || act["city"],
          average_heartrate: (act["avg_hr"] || act["average_heartrate"] || 0).to_f.nonzero?,
          average_speed: (act["avg_speed"] || act["average_speed"] || 0).to_f.nonzero?,
          elevation_gain: (act["total_elevation"] || act["elevation"] || act["elevation_gain"] || 0).to_f.nonzero?,
          source: "xingzhe"
        }

        upsert_activity(attrs)
        true
      end

      def map_sport(sport)
        return "other" unless sport
        case sport.to_s.downcase
        when /riding|cycling|bike|ride/ then "ride"
        when /running|run/ then "run"
        when /walking|walk/ then "walk"
        when /swimming|swim/ then "swim"
        when /hiking|hike/ then "hike"
        when /skiing|ski/ then "ski"
        when /workout/ then "workout"
        else "other"
        end
      end

      def parse_time(str)
        return nil unless str
        normalized = str.to_s.tr(".", "-")
        Time.parse(normalized).strftime("%Y-%m-%d %H:%M:%S")
      rescue
        nil
      end

    end
  end
end

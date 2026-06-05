require_relative "base"

module Workouts
  module Sync
    class IGPSPORT < Base
      BASE_URL = "https://prod.zh.igpsport.com/service"
      LOGIN_URL = "#{BASE_URL}/auth/account/login"
      QUERY_URL = "#{BASE_URL}/web-gateway/web-analyze/activity/queryMyActivity"

      EXERCISE_MAP = {
        0 => "ride",
        1 => "run",
        2 => "hike",
        3 => "walk",
        4 => "swim",
        5 => "ski",
        6 => "workout"
      }.freeze

      def initialize(...)
        super
        @phone = @config["phone"]
        @password = @config["password"]
      end

      def call
        return 0 if @phone.nil? || @password.nil?

        return 0 unless login

        sync_activities
      end

      private

      def login
        resp = Faraday.post(LOGIN_URL,
          JSON.generate({ appId: "igpsport-web", username: @phone, password: @password }),
          { "Content-Type" => "application/json" }
        )
        return false unless resp.status == 200

        data = JSON.parse(resp.body)
        @token = data.dig("data", "access_token")
        return false unless @token

        @auth_headers = { "Authorization" => "Bearer #{@token}" }
        true
      end

      def sync_activities
        existing = existing_run_ids
        page = 1
        count = 0

        loop do
          rows = fetch_page(page)
          break if rows.nil? || rows.empty?

          rows.each do |act|
            ride_id = act["rideId"].to_s
            next if existing.include?(ride_id)

            attrs = build_attrs(act, ride_id)
            next unless attrs

            upsert_activity(attrs)
            count += 1
            report_progress(count)
          end

          page += 1
        end

        count
      end

      def fetch_page(page)
        resp = Faraday.get(QUERY_URL,
          { pageNo: page, pageSize: 20, sort: 1, reqType: 0 },
          @auth_headers
        )
        return nil unless resp.status == 200

        JSON.parse(resp.body).dig("data", "rows")
      end

      def build_attrs(act, ride_id)
        type = map_sport(act["exerciseType"])
        start_t = parse_date(act["startTime"])

        distance = act["rideDistance"].to_f
        moving_time = (act["totalMovingTime"] || act["recordTime"]).to_i
        avg_speed = act["avgSpeed"].to_f

        {
          run_id: "igpsport_#{ride_id}",
          name: act["title"] || "iGPSPORT Activity",
          distance: distance,
          moving_time: moving_time > 0 ? moving_time : nil,
          elapsed_time: moving_time > 0 ? moving_time : nil,
          sport_category: type,
          sport_type: EXERCISE_MAP[act["exerciseType"]] || "ride",
          start_date: start_t,
          start_date_local: start_t,
          location_country: nil,
          average_heartrate: nil,
          average_speed: avg_speed > 0 ? avg_speed : nil,
          elevation_gain: act["totalAscent"].to_f.nonzero?,
          source: "igpsport"
        }
      end

      def map_sport(exercise_type)
        EXERCISE_MAP[exercise_type] || "other"
      end

      def parse_date(str)
        return nil unless str
        normalized = str.to_s.tr(".", "-")
        Time.parse(normalized)
      rescue
        nil
      end

      def existing_run_ids
        @db[:activities].where(source: "igpsport").select_map(:run_id)
          .map { |id| id.sub("igpsport_", "") }
      end
    end
  end
end

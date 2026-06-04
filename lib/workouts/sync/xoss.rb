require_relative "base"

module Workouts
  module Sync
    class XOSS < Base
      BASE_URL = "https://backend.xoss.co/api"
      LOGIN_PATH = "/api/v1/jwt-token/"
      ACTIVITIES_PATH = "/api/v3/activity/"

      SPORT_MAP = {
        1 => "run",
        2 => "ride",
        3 => "other",
        4 => "workout",
        5 => "swim",
        11 => "walk"
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

      def http_request(method, path, body: nil, params: nil, headers: {})
        uri = URI("https://backend.xoss.co#{path}")
        uri.query = URI.encode_www_form(params) if params

        req = case method
              when :get then Net::HTTP::Get.new(uri)
              when :post then Net::HTTP::Post.new(uri)
              end

        headers.each { |k, v| req[k] = v }
        req.body = body if body

        http = Net::HTTP.new(uri.host, uri.port, nil, nil, nil, nil)
        http.use_ssl = true
        http.open_timeout = 30
        http.read_timeout = 60
        resp = http.start { |h| h.request(req) }
        resp
      end

      def login
        resp = http_request(:post, LOGIN_PATH,
          body: JSON.generate({ email: @email, password: @password }),
          headers: { "Content-Type" => "application/json", "Origin" => "xoss" }
        )
        return false unless resp.code.to_i == 200

        data = JSON.parse(resp.body)
        return false unless data["code"] == 0

        @access_token = data.dig("data", "access")
        return false unless @access_token

        @auth_headers = { "Authorization" => "Bearer #{@access_token}", "Origin" => "xoss" }
        true
      end

      def sync_activities
        existing = existing_run_ids
        offset = 1
        limit = 50
        count = 0

        loop do
          activities = fetch_page(offset, limit)
          break if activities.nil? || activities.empty?

          activities.each do |act|
            act_id = act["id"].to_s
            next if existing.include?(act_id)

            count += 1 if process_activity(act)
          end

          offset += limit
        end

        count
      end

      def fetch_page(offset, limit)
        resp = http_request(:get, ACTIVITIES_PATH,
          params: { offset: offset, limit: limit },
          headers: @auth_headers
        )
        return nil unless resp.code.to_i == 200

        JSON.parse(resp.body).dig("data", "results")
      end

      def process_activity(act)
        act_id = act["id"].to_s
        type = map_sport(act["sport"])

        start_t = Time.at(act["start_timestamp"]).utc rescue nil
        return false unless start_t

        distance = act["distance"].to_f
        moving_time = act["duration"].to_i
        avg_speed = distance > 0 && moving_time > 0 ? (distance / moving_time).round(2) : nil

        attrs = {
          run_id: "xoss_#{act_id}",
          name: act["title"] || "XOSS Activity",
          distance: distance,
          moving_time: moving_time > 0 ? moving_time : nil,
          elapsed_time: moving_time > 0 ? moving_time : nil,
          sport_category: type,
          sport_type: act["sub_sport"].to_s,
          start_date: start_t.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: start_t.strftime("%Y-%m-%d %H:%M:%S"),
          location_country: nil,
          average_heartrate: nil,
          average_speed: avg_speed,
          elevation_gain: act["elevation_gain"].to_f.nonzero?,
          source: "xoss"
        }

        upsert_activity(attrs)
        true
      end

      def map_sport(sport)
        SPORT_MAP[sport] || "other"
      end

      def existing_run_ids
        @db[:activities].where(source: "xoss").select_map(:run_id)
          .map { |id| id.sub("xoss_", "") }
      end
    end
  end
end

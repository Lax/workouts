require_relative "base"

module Workouts
  module Sync
    class IGPSPORT < Base
      BASE_URL = "https://prod.zh.igpsport.com/service"
      LOGIN_URL = "#{BASE_URL}/auth/account/login"
      QUERY_URL = "#{BASE_URL}/web-gateway/web-analyze/activity/queryMyActivity"
      DOWNLOAD_INFO_URL = "#{BASE_URL}/web-gateway/web-analyze/activity/getDownloadUrl"

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

            count += 1 if process_activity(ride_id)
          end

          page += 1
        end

        count
      end

      def fetch_page(page)
        resp = Faraday.get(QUERY_URL,
          { pageNo: page, pageSize: 20, sort: 1, reqType: 2 },
          @auth_headers
        )
        return nil unless resp.status == 200

        JSON.parse(resp.body).dig("data", "rows")
      end

      def process_activity(ride_id)
        tcx_content = download_tcx(ride_id)
        return false unless tcx_content

        parser = Parser::TCX.new(source: "igpsport")
        activities = parser.call(tcx_content)
        return false if activities.empty?

        activities.each do |act|
          act[:run_id] = "igpsport_#{ride_id}"
          act[:source] = "igpsport"
          upsert_activity(act)
        end

        true
      end

      def download_tcx(ride_id)
        resp = Faraday.get("#{DOWNLOAD_INFO_URL}/#{ride_id}", {}, @auth_headers)
        return nil unless resp.status == 200

        download_url = JSON.parse(resp.body)["data"]
        return nil unless download_url

        file_resp = Faraday.get(download_url)
        return nil unless file_resp.status == 200

        file_resp.body
      end

      def existing_run_ids
        @db[:activities].where(source: "igpsport").select_map(:run_id)
          .map { |id| id.sub("igpsport_", "") }
      end
    end
  end
end

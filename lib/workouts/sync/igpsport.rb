require_relative "base"

module Workouts
  module Sync
    class IGPSPORT < Base
      BASE_URL = "https://prod.zh.igpsport.com/service"
      LOGIN_URL = "#{BASE_URL}/auth/account/login"
      QUERY_URL = "#{BASE_URL}/web-gateway/web-analyze/activity/queryMyActivity"
      DOWNLOAD_URL = "#{BASE_URL}/web-gateway/web-analyze/activity/getDownloadUrl"

      EXERCISE_MAP = {
        0 => "ride", 1 => "run", 2 => "hike", 3 => "walk",
        4 => "swim", 5 => "ski", 6 => "workout"
      }.freeze

      RAW_EXT = "fit"

      def initialize(...)
        super
        @phone = @config["phone"]
        @password = @config["password"]
      end

      def call
        @start_time = Time.now
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

            next if existing.include?(ride_id) && raw_file_exists?(ride_id)
            break if time_expired?

            synced = sync_activity(act, ride_id)
            count += 1 if synced
            report_progress(count) if synced
          end

          page += 1
        end

        count
      end

      def sync_activity(act, ride_id)
        url = get_download_url(ride_id)
        return false unless url

        download_fit(url, ride_id)

        fit_path = raw_path(ride_id)
        return false unless File.exist?(fit_path)

        wgs_points = FIT::Decoder.decode(fit_path)
        return false if wgs_points.empty?

        first_ts = wgs_points.first["timestamp"]
        if first_ts
          fit_epoch = Time.new(1989, 12, 31, 0, 0, 0, "+00:00").to_i
          t = Time.at(fit_epoch + first_ts)
          @fit_start_utc = t.utc
          @fit_start_local = t.getlocal("+08:00")
        end

        write_standardized_json(wgs_points, ride_id)
        polyline = Geo::Polyline.encode(wgs_points.map { |pt| [pt["positionLat"], pt["positionLong"]] })

        attrs = build_attrs(act, ride_id, polyline)
        return false unless attrs

        upsert_activity(attrs)
        true
      end

      def get_download_url(ride_id)
        resp = Faraday.get("#{DOWNLOAD_URL}/#{ride_id}", {}, @auth_headers)
        return nil unless resp.status == 200
        JSON.parse(resp.body)["data"]
      end

      def download_fit(url, ride_id)
        resp = Faraday.get(url)
        return false unless resp.status == 200

        dir = raw_dir
        FileUtils.mkdir_p(dir)
        tmp = File.join(dir, ".#{ride_id}.#{RAW_EXT}.tmp")
        final = File.join(dir, "#{ride_id}.#{RAW_EXT}")
        File.write(tmp, resp.body, mode: "wb")
        File.rename(tmp, final)
        true
      end

      def fit_to_polyline(ride_id)
        fit_path = raw_path(ride_id)
        return nil unless File.exist?(fit_path)

        wgs_points = FIT::Decoder.decode(fit_path)
        return nil if wgs_points.empty?

        Geo::Polyline.encode(wgs_points.map { |pt| [pt["positionLat"], pt["positionLong"]] })
      end

      def write_standardized_json(wgs_points, ride_id)
        dir = std_dir
        FileUtils.mkdir_p(dir)
        tmp = File.join(dir, ".#{ride_id}.json.tmp")
        final = File.join(dir, "#{ride_id}.json")
        File.write(tmp, JSON.generate(wgs_points))
        File.rename(tmp, final)
      end

      def fetch_page(page)
        resp = Faraday.get(QUERY_URL,
          { pageNo: page, pageSize: 20, sort: 1, reqType: 0 },
          @auth_headers
        )
        return nil unless resp.status == 200
        JSON.parse(resp.body).dig("data", "rows")
      end

      def build_attrs(act, ride_id, polyline = nil)
        type = map_sport(act["exerciseType"])
        start_t = @fit_start_utc || parse_date(act["startTime"])
        start_t_local = @fit_start_local || start_t
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
          start_date: start_t.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: start_t_local.strftime("%Y-%m-%d %H:%M:%S"),
          location_country: nil,
          average_heartrate: nil,
          average_speed: avg_speed > 0 ? avg_speed : nil,
          elevation_gain: act["totalAscent"].to_f.nonzero?,
          summary_polyline: polyline,
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

      def raw_path(platform_id)
        File.join(raw_dir, "#{platform_id}.#{RAW_EXT}")
      end
    end
  end
end

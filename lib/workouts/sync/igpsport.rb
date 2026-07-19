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

      def before_call
        return false if @phone.nil? || @password.nil?
        super
      end

      def authenticate
        login
      end

      def pending_ids
        existing = existing_run_ids
        ids = []
        page = 1
        loop do
          acts = fetch_page(page)
          break if acts.nil? || acts.empty?
          acts.each do |act|
            ride_id = act["rideId"].to_s
            next if existing.include?(ride_id) && raw_file_exists?(ride_id)
            type = map_sport(act["exerciseType"])
            next if skip_type?(type)
            ids << { id: ride_id, type: type, summary: act }
          end
          page += 1
        end
        ids
      end

      def process_one(pending)
        sync_activity(pending[:summary], pending[:id])
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
        pending_ids.filter_map { |p| process_one(p) }.size
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
        sensor_summary = compute_sensor_summary(wgs_points)

        attrs = build_attrs(act, ride_id, polyline, sensor_summary)
        return false unless attrs

        upsert_activity(attrs)
        attrs
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

      def build_attrs(act, ride_id, polyline = nil, sensor = {})
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
          start_date: start_t.iso8601,
          start_date_local: start_t_local.iso8601,
          location_country: nil,
          average_heartrate: act["avgHrm"]&.to_f&.nonzero?,
          max_heartrate: act["maxHrm"]&.to_f&.nonzero?,
          average_cadence: sensor[:average_cadence],
          max_cadence: sensor[:max_cadence],
          average_power: sensor[:average_power],
          max_power: sensor[:max_power],
          calories: sensor[:calories],
          average_temperature: sensor[:average_temperature],
          average_speed: avg_speed > 0 ? avg_speed : nil,
          elevation_gain: act["totalAscent"].to_f.nonzero?,
          summary_polyline: polyline,
          source: "igpsport"
        }
      end

      def compute_sensor_summary(records)
        return {} if records.empty?

        cad = records.map { |r| r["cadence"] }.compact
        pow = records.map { |r| r["power"] }.compact
        tmp = records.map { |r| r["temperature"] }.compact

        {
          average_cadence: cad.any? ? (cad.sum.to_f / cad.size).round(1) : nil,
          max_cadence: cad.max,
          average_power: pow.any? ? (pow.sum.to_f / pow.size).round(1) : nil,
          max_power: pow.max,
          average_temperature: tmp.any? ? (tmp.sum.to_f / tmp.size).round(1) : nil,
          calories: nil
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

require "base64"
require "zlib"
require "openssl"
require "time"

module Workouts
  module Sync
    class Keep < Base
      LOGIN_URL = "https://api.gotokeep.com/v1.1/users/login"
      STATS_URL = "https://api.gotokeep.com/pd/v3/stats/detail?dateUnit=all&type=%{sport}&lastDate=%{last_date}"
      LOG_URL = "https://api.gotokeep.com/pd/v3/%{sport}log/%{run_id}"

      AES_KEY = Base64.decode64("NTZmZTU5OzgyZzpkODczYw==")
      AES_IV = Base64.decode64("MjM0Njg5MjQzMjkyMDMwMA==")

      KEEP_TYPES = %w[running hiking cycling].freeze

      TYPE_MAP = {
        "outdoorWalking" => "walk",
        "outdoorRunning" => "run",
        "outdoorCycling" => "ride",
        "indoorRunning" => "run",
        "mountaineering" => "hike"
      }.freeze

      STRAVA_TYPE_MAP = {
        "outdoorWalking" => "Walk",
        "outdoorRunning" => "Run",
        "outdoorCycling" => "Ride",
        "indoorRunning" => "VirtualRun",
        "mountaineering" => "Hiking"
      }.freeze

      TIMESTAMP_THRESHOLD = 3_600_000
      HR_THRESHOLD = 100

      def initialize(config:, db:, activity_filter: nil, privacy: nil)
        super
        @phone = @config["phone"] || @config["mobile"]
        @password = @config["password"]
        @headers = {
          "User-Agent" => "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:78.0) Gecko/20100101 Firefox/78.0",
          "Content-Type" => "application/x-www-form-urlencoded;charset=utf-8"
        }
        @session = nil
      end

      def call
        return 0 if @phone.nil? || @password.nil?

        @session = login
        return 0 unless @session

        @existing_ids = existing_run_ids

        count = 0
        KEEP_TYPES.each do |sport|
          count += sync_sport_type(sport)
        end
        count
      end

      private

      def http_post(url, body, headers)
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        headers.each { |k, v| req[k] = v }
        req.body = body.is_a?(Hash) ? URI.encode_www_form(body) : body
        http = Net::HTTP.new(uri.host, uri.port, nil, nil, nil, nil)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 30
        http.read_timeout = 60
        http.start { |h| h.request(req) }
      end

      def http_get(url, headers)
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        headers.each { |k, v| req[k] = v }
        http = Net::HTTP.new(uri.host, uri.port, nil, nil, nil, nil)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 30
        http.read_timeout = 60
        http.start { |h| h.request(req) }
      end

      def login
        resp = http_post(LOGIN_URL, { mobile: @phone, password: @password }, @headers)
        return nil unless resp.code.to_i == 200

        data = JSON.parse(resp.body)
        token = data.dig("data", "token")
        return nil unless token

        @headers["Authorization"] = "Bearer #{token}"
        @session = true
      rescue JSON::ParserError
        nil
      end

      def sync_sport_type(sport)
        run_ids = fetch_run_ids(sport)
        new_ids = run_ids.reject { |id| @existing_ids.include?("keep_#{id}") }
        total = new_ids.size
        synced = 0
        new_ids.each do |id|
          synced += 1 if sync_single_run(id, sport)
          report_progress(synced, total)
        end
        synced
      end

      def existing_run_ids
        @db[:activities].where(source: "keep").select_map(:run_id).map(&:to_s)
      end

      def fetch_run_ids(sport)
        ids = []
        last_date = 0

        loop do
          url = STATS_URL % { sport: sport, last_date: last_date }
          resp = @session ? http_get(url, @headers) : nil
          break unless resp&.code&.to_i == 200

          data = JSON.parse(resp.body)["data"]
          break unless data

          records = data["records"] || []
          records.each do |r|
            logs = r["logs"] || []
            logs.each do |log|
              stats = log["stats"] || log
              ids << stats["id"] unless stats["isDoubtful"]
            end
          end

          last_date = data["lastTimestamp"]
          break if last_date.nil? || last_date.zero?

          spider_sleep
        end

        ids
      rescue JSON::ParserError
        ids
      end

      def sync_single_run(run_id, sport)
        url = LOG_URL % { sport: sport, run_id: run_id }
        resp = http_get(url, @headers)
        return false unless resp.code.to_i == 200

        data = JSON.parse(resp.body)
        run_data = data["data"]
        return false unless run_data

        track = build_activity(run_data)
        return false unless track

        upsert_activity(track)
        true
      rescue JSON::ParserError
        false
      end

      def build_activity(run_data)
        keep_id = extract_id(run_data["id"])
        return nil unless keep_id

        start_time = run_data["startTime"]
        end_time = run_data["endTime"]
        duration = run_data["duration"]
        return nil unless duration

        start_date = Time.at(start_time / 1000.0).utc
        data_type = run_data["dataType"]

        geo_points = decode_geo_points(run_data["geoPoints"])
        hr_data = decode_hr_data(run_data.dig("heartRate", "heartRates"))

        avg_hr = run_data.dig("heartRate", "averageHeartRate")
        avg_hr = nil if avg_hr && avg_hr < 0

        polyline_str = nil
        total_elevation = run_data["elevation"]
        computed_distance = run_data["distance"]

        if geo_points&.any?
          use_absolute_ts = geo_points.first["timestamp"].to_i > TIMESTAMP_THRESHOLD
          effective_start = use_absolute_ts ? 0 : start_time

          wgs_points = geo_points.map do |p|
            lat, lng = Geo::CoordTransform.gcj02_to_wgs84_exact(p["latitude"], p["longitude"])
            ts = p["timestamp"] || p["unixTimestamp"]
            pt_time = ts ? Time.at(effective_start / 1000.0 + ts.to_i / 10.0).utc : nil
            hr = find_nearest_hr(hr_data, ts, start_time)
            [lat, lng, p["altitude"], pt_time, hr]
          end

          if wgs_points.any? { |pt| pt[3] }
            computed_distance ||= total_distance_haversine(wgs_points)
            total_elevation ||= elevation_gain_from_points(wgs_points)
          end

          polyline_str = Geo::Polyline.encode(wgs_points.map { |pt| [pt[0], pt[1]] })
          avg_hr ||= compute_avg_hr(wgs_points)
        end

        moving_time = duration
        elapsed_time = ((end_time - start_time) / 1000.0).round

        {
          run_id: "keep_#{keep_id}",
          name: "#{STRAVA_TYPE_MAP[data_type] || data_type} from keep",
          distance: computed_distance&.round(2),
          moving_time: moving_time,
          elapsed_time: elapsed_time,
          sport_category: TYPE_MAP[data_type] || "other",
          sport_type: data_type,
          start_date: start_date.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: start_date.strftime("%Y-%m-%d %H:%M:%S"),
          location_country: run_data["region"],
          summary_polyline: polyline_str,
          average_heartrate: avg_hr&.round(1),
          average_speed: computed_distance && moving_time&.positive? ? (computed_distance.to_f / moving_time).round(2) : nil,
          elevation_gain: total_elevation&.round(1),
          source: "keep"
        }
      end

      def extract_id(id_str)
        return nil unless id_str
        id_str.split("_")[1]
      end

      def decode_geo_points(geo_data)
        return nil unless geo_data
        raw = Base64.decode64(geo_data)
        decrypted = aes_decrypt(raw)
        decompressed = zlib_inflate(decrypted)
        JSON.parse(decompressed)
      rescue StandardError
        nil
      end

      def decode_hr_data(hr_data)
        return nil unless hr_data
        raw = Base64.decode64(hr_data)
        decompressed = zlib_inflate(raw)
        JSON.parse(decompressed)
      rescue StandardError
        nil
      end

      def aes_decrypt(data)
        cipher = OpenSSL::Cipher.new("AES-128-CBC")
        cipher.decrypt
        cipher.key = AES_KEY
        cipher.iv = AES_IV
        cipher.update(data) + cipher.final
      end

      def zlib_inflate(data)
        [-Zlib::MAX_WBITS, Zlib::MAX_WBITS, Zlib::MAX_WBITS + 16].each do |wbits|
          begin
            inflater = Zlib::Inflate.new(wbits)
            result = inflater.inflate(data)
            inflater.finish rescue nil
            inflater.close
            return result
          rescue Zlib::DataError
            next
          end
        end
        raise Zlib::DataError, "cannot inflate data"
      end

      def find_nearest_hr(hr_data, geo_ts, start_time, threshold: HR_THRESHOLD)
        return nil unless hr_data&.any? && geo_ts

        normalize = ->(ts) {
          if ts > TIMESTAMP_THRESHOLD
            ts - start_time / 100
          else
            ts
          end
        }

        target = normalize.call(geo_ts)

        nearest = nil
        min_diff = Float::INFINITY

        hr_data.each do |item|
          ts = item["timestamp"]
          next unless ts

          diff = (normalize.call(ts) - target).abs
          if diff <= threshold && diff < min_diff
            nearest = item
            min_diff = diff
          end
        end

        hr = nearest&.dig("beatsPerMinute")
        hr&.positive? ? hr : nil
      end

      def compute_avg_hr(points)
        hrs = points.map { |p| p[4] }.compact
        return nil if hrs.empty?
        hrs.sum / hrs.size
      end

      def total_distance_haversine(points)
        return 0.0 if points.length < 2
        total = 0.0
        (1...points.length).each do |i|
          total += haversine_dist(points[i - 1], points[i])
        end
        total
      end

      def haversine_dist(p1, p2)
        lat1 = p1[0] * Math::PI / 180.0
        lat2 = p2[0] * Math::PI / 180.0
        dlat = (p2[0] - p1[0]) * Math::PI / 180.0
        dlon = (p2[1] - p1[1]) * Math::PI / 180.0

        a = Math.sin(dlat / 2) ** 2 +
            Math.cos(lat1) * Math.cos(lat2) *
            Math.sin(dlon / 2) ** 2
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        6371000.0 * c
      end

      def elevation_gain_from_points(points)
        total = 0.0
        (1...points.length).each do |i|
          elev1 = points[i - 1][2] || 0.0
          elev2 = points[i][2] || 0.0
          gain = elev2 - elev1
          total += gain if gain > 0
        end
        total
      end

      def spider_sleep
        sleep 0.1
      end
    end
  end
end

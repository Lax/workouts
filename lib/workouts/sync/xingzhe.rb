# frozen_string_literal: true

require_relative "base"
require "fileutils"
require "openssl"

module Workouts
  module Sync
    class XingZhe < Base
      BASE_HOST = "www.imxingzhe.com"
      LOGIN_PATH = "/api/v1/user/login/"
      WORKOUTS_PATH = "/api/v1/pgworkout/"
      STREAM_PATH = "/api/v1/pgworkout/"
      DETAIL_PATH = "/api/v1/pgworkout/"
      RSA_PUBKEY = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDmuQkBbijudDAJgfffDeeIButqWHZvUwcRuvWdg89393FSdz3IJUHc0rgI/S3WuU8N0VePJLmVAZtCOK4qe4FY/eKmWpJmn7JfXB4HTMWjPVoyRZmSYjW4L8GrWmh51Qj7DwpTADadF3aq04o+s1b8LXJa8r6+TIqqL5WUHtRqmQIDAQAB"

      SPORT_MAP = {
        3 => "ride", 1 => "run", 2 => "hike",
        5 => "swim", 6 => "walk", 11 => "ski", 13 => "workout"
      }.freeze

      RAW_EXT = "json"

      def initialize(...)
        super
        @email = @config["email"]
        @password = @config["password"]
      end

      def before_call
        return false if @email.nil? || @password.nil?
        super
      end

      def authenticate
        login
      end

      def pending_ids
        existing = existing_run_ids
        ids = []
        offset = 0
        limit = 50
        loop do
          acts = fetch_page(offset, limit)
          break if acts.nil? || acts.empty?
          acts.each do |act|
            aid = act["id"].to_s
            next if existing.include?(aid) && raw_file_exists?(aid)
            type = map_sport(act["sport"])
            next if skip_type?(type)
            ids << { id: aid, type: type, summary: act }
          end
          offset += limit
        end
        ids
      end

      def process_one(pending)
        process_activity(pending[:summary], pending[:type])
      end

      private

      def http_request(method, path, body: nil, params: nil, headers: {})
        uri = URI("https://#{BASE_HOST}#{path}")
        uri.query = URI.encode_www_form(params) if params

        req = case method
              when :get then Net::HTTP::Get.new(uri)
              when :post then Net::HTTP::Post.new(uri)
              end

        headers.each { |k, v| req[k] = v }
        req.body = body if body

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 30
        http.read_timeout = 60
        http.start { |h| h.request(req) }
      end

      def login
        encrypted = rsa_encrypt(@password)
        resp = http_request(:post, LOGIN_PATH,
          body: JSON.generate({ account: @email, password: encrypted }),
          headers: { "Content-Type" => "application/json" }
        )
        return false unless resp.code.to_i == 200

        data = JSON.parse(resp.body)
        return false unless data["code"] == 0

        cookie = extract_cookie(resp)
        return false unless cookie

        @headers = { "Cookie" => cookie, "Accept" => "application/json" }
        true
      end

      def rsa_encrypt(password)
        pem = "-----BEGIN PUBLIC KEY-----\n#{RSA_PUBKEY}\n-----END PUBLIC KEY-----"
        key = OpenSSL::PKey::RSA.new(pem)
        Base64.strict_encode64(key.public_encrypt(password, OpenSSL::PKey::RSA::PKCS1_PADDING))
      end

      def extract_cookie(resp)
        set_cookie = resp["set-cookie"]
        return nil unless set_cookie
        m = set_cookie.match(/sessionid=([^;]+)/)
        m ? "sessionid=#{m[1]}" : nil
      end

      def sync_activities
        pending_ids.filter_map { |p| process_one(p) }.size
      end

      def fetch_page(offset, limit)
        resp = http_request(:get, WORKOUTS_PATH,
          params: { offset: offset, limit: limit },
          headers: @headers
        )
        return nil unless resp.code.to_i == 200

        JSON.parse(resp.body).dig("data", "data")
      end

      def process_activity(act, type)
        aid = act["id"].to_s
        start_t = Time.at(act["start_time"] / 1000.0).utc rescue nil
        return false unless start_t

        attrs = {
          run_id: "xingzhe_#{aid}",
          name: act["title"] || "XingZhe Activity",
          distance: act["distance"].to_f,
          moving_time: (t = act["duration"].to_i) > 0 ? t : nil,
          elapsed_time: t > 0 ? t : nil,
          sport_category: type,
          sport_type: act["sport"].to_s,
          start_date: start_t.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: start_t.strftime("%Y-%m-%d %H:%M:%S"),
          average_speed: (act["avg_speed"].to_f / 3.6).round(2).nonzero?,
          elevation_gain: act["elevation_gain"].to_f.nonzero?,
          source: "xingzhe"
        }

        stream = fetch_stream(aid)
        if stream
          write_raw(stream, aid)
          if (locs = stream["location"]) && locs.size >= 2
            pts = locs.map { |lng, lat| [lat, lng] }
            write_std(pts, stream, aid)
            attrs[:summary_polyline] = stream_to_polyline(aid)
          end
        end

        if attrs[:summary_polyline].nil? && (detail = fetch_activity_detail(aid)) && (segments = detail["segments_km"])
          pts = segments.map { |s| [s["latitude"], s["longitude"]] }
          attrs[:summary_polyline] = Geo::Polyline.encode(pts) if pts.size >= 2
        end

        upsert_activity(attrs)
        attrs
      end

      def raw_path(platform_id)
        File.join(raw_dir, "#{platform_id}.#{RAW_EXT}")
      end

      def fetch_stream(id)
        resp = http_request(:get, "#{STREAM_PATH}#{id}/stream/", headers: @headers || {})
        return nil unless resp.code.to_i == 200

        JSON.parse(resp.body).dig("data")
      rescue JSON::ParserError
        nil
      end

      def write_raw(stream, id)
        dir = raw_dir
        FileUtils.mkdir_p(dir)
        tmp = File.join(dir, ".#{id}.json.tmp")
        final = File.join(dir, "#{id}.json")
        File.write(tmp, JSON.generate({
          source: "xingzhe",
          fetchedAt: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          stream: stream
        }))
        File.rename(tmp, final)
      end

      def write_std(pts, stream, id)
        dir = std_dir
        FileUtils.mkdir_p(dir)
        ts_arr = stream["timestamp"] || []
        alt_arr = stream["altitude"] || []
        spd_arr = stream["speed"] || []
        dst_arr = stream["distance"] || []

        extended = pts.each_with_index.map do |(lat, lng), i|
          ts_val = ts_arr[i]
          {
            latitude: lat, longitude: lng,
            altitude: alt_arr[i],
            timestamp: ts_val ? Time.at(ts_val).utc.strftime("%Y-%m-%dT%H:%M:%SZ") : nil,
            speed: spd_arr[i],
            distance: dst_arr[i]
          }
        end

        tmp = File.join(dir, ".#{id}.json.tmp")
        final = File.join(dir, "#{id}.json")
        File.write(tmp, JSON.generate(extended))
        File.rename(tmp, final)
      end

      def stream_to_polyline(id)
        raw = JSON.parse(File.read(raw_path(id)))
        locs = raw.dig("stream", "location") || []
        return nil if locs.size < 2

        pts = locs.map { |lng, lat| [lat, lng] }
        Geo::Polyline.encode(pts)
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def fetch_activity_detail(id)
        resp = http_request(:get, "#{DETAIL_PATH}#{id}/")
        return nil unless resp.code.to_i == 200

        data = JSON.parse(resp.body)
        data.dig("data", "workout")
      end

      def map_sport(sport)
        SPORT_MAP[sport] || "other"
      end

      def existing_run_ids
        @db[:activities].where(source: "xingzhe").select_map(:run_id)
          .map { |id| id.sub("xingzhe_", "") }
      end
    end
  end
end

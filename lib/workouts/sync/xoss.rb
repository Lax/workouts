require_relative "base"
require "fileutils"

module Workouts
  module Sync
    class XOSS < Base
      FIT_FILE_PATH = "/api/v3/activity/%<id>s/fit_file/"
      BASE_URL = "https://backend.xoss.co"
      LOGIN_PATH = "/api/v1/jwt-token/"
      REFRESH_PATH = "/api/v1/jwt-token/refresh/"
      ACTIVITIES_PATH = "/api/v3/activity/"
      ACCESS_TOKEN_TTL = 86400

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
        @token_path = @config["token_path"] || File.join("data", "cache", "xoss_tokens.json")
      end

      def call
        @start_time = Time.now
        return 0 if @email.nil? || @password.nil?
        return 0 unless authenticate
        sync_activities
      end

      private

      def authenticate
        return true if load_tokens && access_token_valid?
        return true if refresh_access_token
        return true if login
        false
      end

      def http_request(method, path, body: nil, params: nil, headers: {})
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params) if params

        req = case method
              when :get then Net::HTTP::Get.new(uri)
              when :post then Net::HTTP::Post.new(uri)
              end

        headers.each { |k, v| req[k] = v }
        req.body = body if body

        proxy = proxy_uri
        http = if proxy
                 Net::HTTP.new(uri.host, uri.port, proxy.host, proxy.port, proxy.user, proxy.password)
               else
                 Net::HTTP.new(uri.host, uri.port)
               end
        http.use_ssl = true
        http.open_timeout = 30
        http.read_timeout = 60
        http.start { |h| h.request(req) }
      end

      def proxy_uri
        uri = URI(ENV["http_proxy"] || ENV["HTTP_PROXY"] || ENV["https_proxy"] || ENV["HTTPS_PROXY"] || "")
        uri.host ? uri : nil
      end

      def login
        retries ||= 0
        resp = http_request(:post, LOGIN_PATH,
          body: JSON.generate({ email: @email, password: @password }),
          headers: { "Content-Type" => "application/json", "Origin" => "xoss" }
        )
        return false unless resp.code.to_i == 200

        data = JSON.parse(resp.body)
        return false unless data["code"] == 0

        @access_token = data.dig("data", "access")
        @refresh_token = data.dig("data", "refresh")
        return false unless @access_token

        @auth_headers = { "Authorization" => "Bearer #{@access_token}", "Origin" => "xoss" }
        save_tokens
        true
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        if (retries += 1) <= 2
          sleep 2
          retry
        end
        raise SyncError, "XOSS login timeout: #{e.message}"
      end

      def token_path
        @token_path
      end

      def load_tokens
        return false unless File.exist?(token_path)

        data = JSON.parse(File.read(token_path))
        @access_token = data["access"]
        @refresh_token = data["refresh"]
        @expires_at = data["expires_at"]
        @auth_headers = { "Authorization" => "Bearer #{@access_token}", "Origin" => "xoss" } if @access_token
        true
      rescue => e
        warn "XOSS: failed to load cached tokens: #{e.message}"
        false
      end

      def save_tokens
        return unless @access_token

        FileUtils.mkdir_p(File.dirname(token_path))
        File.write(token_path, JSON.generate({
          access: @access_token,
          refresh: @refresh_token,
          expires_at: @expires_at || Time.now.to_i + ACCESS_TOKEN_TTL
        }))
      rescue => e
        warn "XOSS: failed to save tokens: #{e.message}"
      end

      def remove_stale_tokens
        File.delete(token_path) if File.exist?(token_path)
      rescue => e
        warn "XOSS: failed to remove stale tokens: #{e.message}"
      end

      def access_token_valid?
        return false unless @access_token
        return false unless @expires_at
        Time.now.to_i < @expires_at - 60
      end

      def refresh_access_token
        return false unless @refresh_token

        retries ||= 0
        resp = http_request(:post, REFRESH_PATH,
          body: JSON.generate({ refresh: @refresh_token }),
          headers: { "Content-Type" => "application/json", "Origin" => "xoss" }
        )
        unless resp.code.to_i == 200
          remove_stale_tokens
          return false
        end

        data = JSON.parse(resp.body)
        unless data["code"] == 0
          remove_stale_tokens
          return false
        end

        @access_token = data.dig("data", "access")
        @refresh_token = data.dig("data", "refresh")
        return false unless @access_token

        @expires_at = Time.now.to_i + ACCESS_TOKEN_TTL
        @auth_headers = { "Authorization" => "Bearer #{@access_token}", "Origin" => "xoss" }
        save_tokens
        true
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        if (retries += 1) <= 2
          sleep 2
          retry
        end
        raise SyncError, "XOSS token refresh timeout: #{e.message}"
      end

      def raw_path(platform_id)
        File.join(raw_dir, "#{platform_id}.fit")
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
            next if existing.include?(act_id) && raw_file_exists?(act_id)
            break if time_expired?

            type = map_sport(act["sport"])
            next if skip_type?(type)

            result = process_activity(act)
            if result
              count += 1
              report_progress(count, nil, build_progress_info(result))
            end
          end

          offset += limit
        end

        count
      end

      def fetch_page(offset, limit)
        retries ||= 0
        resp = http_request(:get, ACTIVITIES_PATH,
          params: { offset: offset, limit: limit },
          headers: @auth_headers
        )
        return nil unless resp.code.to_i == 200

        JSON.parse(resp.body).dig("data", "results")
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        if (retries += 1) <= 2
          sleep 2
          retry
        end
        raise SyncError, "XOSS fetch timeout: #{e.message}"
      rescue JSON::ParserError
        if (retries ||= 0; (retries += 1) <= 2)
          sleep 2
          retry
        end
        nil
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
          average_speed: avg_speed,
          elevation_gain: act["elevation_gain"].to_f.nonzero?,
          calories: act["total_calories"]&.to_i&.nonzero?,
          source: "xoss"
        }

        if act["fit_file_hash"].to_s != ""
          fit_data = download_fit(act_id)
          if fit_data
            write_raw(fit_data, act_id)
            begin
              wgs_points = FIT::Decoder.decode(raw_path(act_id))
            rescue => e
              warn "XOSS: FIT decode failed for #{act_id}: #{e.message}"
              wgs_points = []
            end
            if wgs_points.any?
              write_std(wgs_points, act_id)
              pts = wgs_points.map { |pt| [pt["positionLat"], pt["positionLong"]] }
              attrs[:summary_polyline] = Geo::Polyline.encode(pts)
              attrs.merge!(compute_sensor_summary(wgs_points))
            end
          end
        end

        upsert_activity(attrs)
        attrs
      end

      def download_fit(act_id)
        resp = http_request(:get, format(FIT_FILE_PATH, id: act_id), headers: @auth_headers)
        return nil unless resp.code.to_i == 302

        fit_uri = URI(resp["location"])
        fit_http = Net::HTTP.new(fit_uri.host, fit_uri.port)
        fit_http.use_ssl = fit_uri.scheme == "https"
        fit_http.open_timeout = 60
        fit_http.read_timeout = 180
        fit_resp = fit_http.start { |h| h.request(Net::HTTP::Get.new(fit_uri)) }
        return nil unless fit_resp.code.to_i == 200

        fit_resp.body
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        warn "XOSS: FIT download timeout for #{act_id}: #{e.message}"
        nil
      end

      def write_raw(binary, act_id)
        dir = raw_dir
        FileUtils.mkdir_p(dir)
        tmp = File.join(dir, ".#{act_id}.fit.tmp")
        final = File.join(dir, "#{act_id}.fit")
        File.write(tmp, binary, mode: "wb")
        File.rename(tmp, final)
      end

      def write_std(points, act_id)
        dir = std_dir
        FileUtils.mkdir_p(dir)
        tmp = File.join(dir, ".#{act_id}.json.tmp")
        final = File.join(dir, "#{act_id}.json")
        File.write(tmp, JSON.generate(points))
        File.rename(tmp, final)
      end

      def compute_sensor_summary(records)
        return {} if records.empty?

        cad = records.map { |r| r["cadence"] }.compact
        pow = records.map { |r| r["power"] }.compact
        tmp = records.map { |r| r["temperature"] }.compact
        hr = records.map { |r| r["heart_rate"] }.compact

        {
          average_cadence: cad.any? ? (cad.sum.to_f / cad.size).round(1) : nil,
          max_cadence: cad.max,
          average_power: pow.any? ? (pow.sum.to_f / pow.size).round(1) : nil,
          max_power: pow.max,
          average_temperature: tmp.any? ? (tmp.sum.to_f / tmp.size).round(1) : nil,
          average_heartrate: hr.any? ? (hr.sum.to_f / hr.size).round(1) : nil
        }
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

require_relative "base"
require_relative "../fit/decoder"
require "ostruct"
require "base64"
require "oauth"
require "oauth/request_proxy/net_http"
require "json"
require "net/http"
require "uri"
require "cgi"
require "http/cookie_jar"
require "yaml"
require "fileutils"
require "zip"
require "tzinfo"

module Workouts
  module Sync
    # Garmin OAuth 认证基类（garmin.com / garmin.cn 共用）
    #
    # 认证优先级（依次降级）:
    #   ① secret: config.yml 或 env SYNC__{SOURCE}__SECRET
    #      格式 Base64([OAuth1 JSON, OAuth2 JSON])，与 garth dumps() 兼容
    #      解析后 OAuth2 未过期 → 直接用; 过期 → OAuth1 refresh
    #      失败 → 降级
    #   ② token 文件: ~/.workouts/garmin_tokens.json
    #      文件持久化，逻辑同 ①
    #      失败 → 删除陈旧文件 → 降级
    #   ③ SSO 登录: email + password，交互式，支持 MFA
    #      成功后 dump_secret → verify_access_token
    #      → save_secret_to_config（写回 config.yml）
    #      → save_tokens（写 token 文件）
    #      验证失败 → 不保存，抛出 AuthError
    #
    # CI 环境:
    #   secret 由 env 注入，不走 SSO
    #   OAuth2 每 6h 自动 refresh，OAuth1 长期有效
    #   OAuth1 过期 → 本地重新 auth，更新 GitHub Secret
    class GarminBase < Base
      CLIENT_ID = "GCM_ANDROID_DARK"
      OAUTH_CONSUMER_URL = "https://thegarth.s3.amazonaws.com/oauth_consumer.json"

      SSO_HEADERS = {
        "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9"
      }.freeze

      def initialize(...)
        super
        @domain = "garmin.com"
        @email = @config["email"]
        @password = @config["password"]
        @secret = @config["secret"]
        @ssl_verify = @config.key?("ssl_verify") ? @config["ssl_verify"] : true
      end

      attr_reader :generated_secret

      def before_call
        return false if @email.to_s.empty? && @secret.to_s.empty?
        super
      end

      # 认证优先级链: secret → token 文件 → SSO 登录
      def authenticate
        @oauth_consumer = fetch_oauth_consumer

        if @secret
          if parse_secret_string(@secret)
            return true if access_token_valid?
            begin
              return true if refresh_oauth2_via_oauth1
            rescue AuthError
            end
          end
        end

        begin
          return true if load_tokens && access_token_valid?
          return true if load_tokens && refresh_oauth2_via_oauth1
        rescue AuthError
          remove_stale_tokens
        end

        return false if @email.to_s.empty? || @password.to_s.empty?

        ticket = sso_login
        @oauth1_token = fetch_oauth1_token(ticket)
        @access_token = exchange_oauth2
        @generated_secret = dump_secret
        unless verify_access_token
          @generated_secret = nil
          raise AuthError, "New tokens failed API verify — SSO result invalid"
        end
        save_secret_to_config
        save_tokens
        true
      end

      def pending_ids
        existing = existing_run_ids
        ids = []
        start = 0
        limit = 100
        loop do
          activities = fetch_activity_list(start, limit)
          break if activities.nil? || activities.empty?
          activities.each do |act|
            act_id = act["activityId"].to_s
            type = map_type(act["activityType"])
            next if skip_type?(type)
            next if existing.include?(act_id) && raw_file_exists?(act_id)
            ids << { id: act_id, type: type }
          end
          start += limit
        end
        ids
      end

      def process_one(pending)
        act_id = pending[:id]
        type = pending[:type]

        details = fetch_activity_detail(act_id)
        return nil unless details

        polyline = fetch_summary_polyline(act_id)

        unless raw_file_exists?(act_id)
          download_fit_raw(act_id)
          l2 = fit_to_l2(act_id)
          write_standardized_json(l2, act_id) if l2
        end

        attrs = build_attrs(details, act_id, type, polyline)

        # Resolve start_date_local from GPS timezone
        if (start_t = parse_garmin_time(details.dig("summaryDTO", "startTimeGMT")))
          local_t = resolve_local_time(start_t, act_id, polyline)
          attrs[:start_date_local] = local_t.iso8601 if local_t
        end

        upsert_activity(attrs)
        attrs
      end

      private

      def access_token_valid?
        return false unless @access_token

        expires_at = @access_token["expires_at"] || @saved_expires_at
        expires_at.nil? || Time.now.to_i < expires_at - 60
      end

      # Base64 → [OAuth1 JSON, OAuth2 JSON], 兼容 garth dumps()
      def parse_secret_string(secret)
        decoded = JSON.parse(Base64.strict_decode64(secret))
        o1 = decoded[0]
        o2 = decoded[1]

        secret_domain = o1["domain"]
        @domain = secret_domain if secret_domain
        @oauth1_token = OpenStruct.new(
          oauth_token: o1["oauth_token"],
          oauth_token_secret: o1["oauth_token_secret"],
          mfa_token: o1["mfa_token"],
          domain: @domain
        )
        @access_token = o2
        true
      rescue => e
        puts "Garmin: secret decode failed: #{e.message}"
        puts "  Re-auth: bundle exec exe/workouts auth garmin_cn"
        false
      end

      # [OAuth1, OAuth2] → JSON → Base64, garth dumps() 镜像
      def dump_secret
        o1 = {
          oauth_token: @oauth1_token.oauth_token,
          oauth_token_secret: @oauth1_token.oauth_token_secret,
          mfa_token: @oauth1_token.mfa_token,
          mfa_expiration_timestamp: nil,
          domain: @oauth1_token.domain
        }
        JSON.generate([o1, @access_token]).then { |s| Base64.strict_encode64(s) }
      end

      # SSO 成功后写 secret 到 config.yml，下次走 ①
      def save_secret_to_config
        path = "config/config.yml"
        return unless File.exist?(path)

        cfg = YAML.safe_load(File.read(path)) || {}
        source = @domain == "garmin.cn" ? "garmin_cn" : "garmin"
        cfg["sync"] ||= {}
        cfg["sync"][source] ||= {}
        cfg["sync"][source]["secret"] = @generated_secret
        File.write(path, YAML.dump(cfg))
      rescue => e
        puts "Warning: failed to save secret to config.yml: #{e.message}"
      end

      # SSO 后验证新 token: 拉一条活动确认 API 可访问
      def verify_access_token
        result = api_get("/activitylist-service/activities/search/activities?start=0&limit=1")
        !result.nil?
      rescue => e
        puts "Garmin: API verify failed — token invalid: #{e.message}"
        false
      end

      # 删除陈旧 token 文件，避免下次重试同一过期凭证
      def remove_stale_tokens
        path = token_path
        File.delete(path) if File.exist?(path)
      rescue => e
        puts "Warning: failed to remove stale tokens: #{e.message}"
      end

      # OAuth2 过期: 用 OAuth1 签名换新 OAuth2
      def refresh_oauth2_via_oauth1
        return false unless @oauth1_token&.oauth_token

        @access_token = exchange_oauth2
        @access_token["expires_at"] = Time.now.to_i + (@access_token["expires_in"] || 21600).to_i
        save_tokens
        true
      rescue => e
        raise AuthError, "Garmin OAuth refresh failed: #{e.message}" +
          " — re-auth: bundle exec exe/workouts auth garmin_cn"
      end

      def fetch_oauth_consumer
        resp = Faraday.get(OAUTH_CONSUMER_URL)
        JSON.parse(resp.body)
      end

      def sso_login
        jar = cookie_jar
        sso_base = "https://sso.#{@domain}"

        sso_get(sso_base, "/mobile/sso/en/sign-in", { clientId: CLIENT_ID }, jar)

        service_url = "https://mobile.integration.#{@domain}/gcm/android"
        login_params = { clientId: CLIENT_ID, locale: "en-US", service: service_url }
        login_body = JSON.generate(
          username: @email, password: @password,
          rememberMe: false, captchaToken: ""
        )
        resp = sso_post(sso_base, "/mobile/api/login", login_params, login_body, jar)
        body = JSON.parse(resp.body)
        status = body.dig("responseStatus", "type")

        if status == "MFA_REQUIRED"
          mfa_method = body.dig("customerMfaInfo", "mfaLastMethodUsed") || "email"
          print "MFA code sent via #{mfa_method}. Enter code: "
          $stdout.flush
          mfa_code = $stdin.gets.strip
          mfa_body = JSON.generate(
            mfaMethod: mfa_method,
            mfaVerificationCode: mfa_code,
            rememberMyBrowser: false,
            reconsentList: [],
            mfaSetup: false
          )
          resp = sso_post(sso_base, "/mobile/api/mfa/verifyCode", login_params, mfa_body, jar)
          body = JSON.parse(resp.body)
          status = body.dig("responseStatus", "type")
        end

        unless status == "SUCCESSFUL"
          raise "Garmin login failed (#{body.dig("responseStatus", "message") || status})"
        end

        body["serviceTicketId"]
      end

      def sso_get(base, path, params, jar)
        uri = URI("#{base}#{path}")
        uri.query = URI.encode_www_form(params) if params
        req = Net::HTTP::Get.new(uri)
        SSO_HEADERS.each { |k, v| req[k] = v }
        add_cookies(req, uri, jar)
        resp = send_http(uri, req)
        update_jar(jar, resp, uri)
        resp
      end

      def sso_post(base, path, params, body, jar)
        uri = URI("#{base}#{path}")
        uri.query = URI.encode_www_form(params) if params
        req = Net::HTTP::Post.new(uri)
        SSO_HEADERS.each { |k, v| req[k] = v }
        req["Content-Type"] = "application/json"
        add_cookies(req, uri, jar)
        req.body = body
        resp = send_http(uri, req)
        update_jar(jar, resp, uri)
        resp
      end

      def cookie_jar
        HTTP::CookieJar.new
      end

      def add_cookies(request, uri, jar)
        cookies = jar.cookies(uri)
        return if cookies.empty?
        request["Cookie"] = HTTP::Cookie.cookie_value(cookies)
      end

      def update_jar(jar, response, uri)
        sets = response.get_fields("Set-Cookie") || []
        sets.each { |c| jar.parse(c, uri) }
      end

      def fetch_oauth1_token(ticket)
        base_url = "https://connectapi.#{@domain}/oauth-service/oauth/"
        login_url = "https://mobile.integration.#{@domain}/gcm/android"
        url = "#{base_url}preauthorized?ticket=#{CGI.escape(ticket)}&login-url=#{CGI.escape(login_url)}&accepts-mfa-tokens=true"

        oauth_consumer = OAuth::Consumer.new(
          @oauth_consumer["consumer_key"], @oauth_consumer["consumer_secret"],
          site: "https://connectapi.#{@domain}",
          scheme: :header, signature_method: "HMAC-SHA1"
        )

        sleep(3)

        req = Net::HTTP::Get.new(URI(url))
        req["User-Agent"] = "com.garmin.android.apps.connectmobile"
        oauth_consumer.sign!(req, nil)

        resp = retry_on_429(3, 5) { send_http(URI(url), req) }
        raise "OAuth1 error: #{resp.code}" unless resp.code.to_i == 200

        parsed = CGI.parse(resp.body).transform_keys(&:to_s).transform_values(&:first)

        OpenStruct.new(
          oauth_token: parsed["oauth_token"],
          oauth_token_secret: parsed["oauth_token_secret"],
          mfa_token: parsed["mfa_token"],
          domain: @domain
        )
      end

      def exchange_oauth2
        url = "https://connectapi.#{@domain}/oauth-service/oauth/exchange/user/2.0"

        oauth_consumer = OAuth::Consumer.new(
          @oauth_consumer["consumer_key"], @oauth_consumer["consumer_secret"],
          site: "https://connectapi.#{@domain}",
          scheme: :header, signature_method: "HMAC-SHA1"
        )

        token = OAuth::Token.new(@oauth1_token.oauth_token, @oauth1_token.oauth_token_secret)
        req = Net::HTTP::Post.new(URI(url))
        req["User-Agent"] = "com.garmin.android.apps.connectmobile"
        req["Content-Type"] = "application/x-www-form-urlencoded"
        body_params = { audience: "GARMIN_CONNECT_MOBILE_ANDROID_DI" }
        body_params[:mfa_token] = @oauth1_token.mfa_token if @oauth1_token.mfa_token
        req.body = URI.encode_www_form(body_params)
        oauth_consumer.sign!(req, token)

        resp = retry_on_429 { send_http(URI(url), req) }
        raise "OAuth2 exchange error: #{resp.code}" unless resp.code.to_i == 200

        result = JSON.parse(resp.body)
        result["expires_at"] = Time.now.to_i + (result["expires_in"] || 21600).to_i
        result
      end

      def sync_activities
        @start_time = Time.now
        pending_ids.filter_map { |p| process_one(p) }.size
      end

      def existing_run_ids
        @db[:activities].where(source: source_prefix).select_map(:run_id)
          .map { |id| id.sub("#{source_prefix}_", "") }
      end

      def fetch_activity_list(start, limit)
        api_get("/activitylist-service/activities/search/activities?start=#{start}&limit=#{limit}")
      end

      def fetch_activity_detail(activity_id)
        api_get("/activity-service/activity/#{activity_id}")
      end

      def api_get(path)
        uri = URI("#{connectapi_base}#{path}")
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@access_token["access_token"]}"
        req["User-Agent"] = "GCM-iOS-5.22.1.4"
        resp = retry_on_429 { send_http(uri, req) }
        return nil unless resp.code.to_i == 200
        JSON.parse(resp.body)
      end

      def connectapi_base
        @connectapi_base ||= "https://connectapi.#{@domain}"
      end

      def send_http(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless @ssl_verify
        http.open_timeout = 30
        http.read_timeout = 60
        http.start { |h| h.request(request) }
      end

      def retry_on_429(max_retries = 3, base_delay = 2)
        retries = 0
        loop do
          resp = yield
          return resp unless resp.code.to_i == 429 && retries < max_retries

          retries += 1
          sleep(base_delay * (2 ** retries))
        end
      end

      # ── Timezone resolution ────────────────────────────────────

      def tz_resolver
        @tz_resolver ||= Workouts::Timezone::Resolver.new({})
      end

      # Resolve local time from GPS data. Tries L2 file first,
      # then polyline, then falls back to config default timezone.
      def resolve_local_time(start_utc, activity_id, polyline = nil)
        lat = lng = nil

        # Try L2 file first
        lat, lng = first_gps_from_l2(activity_id)

        # Fallback: polyline
        if lat.nil? && polyline
          decoded = Workouts::Geo::Polyline.decode(polyline) rescue nil
          if decoded && decoded.any?
            lat, lng = decoded.first
          end
        end

        tz_string = tz_resolver.resolve(lat, lng)
        tz = TZInfo::Timezone.get(tz_string)
        tz.utc_to_local(start_utc)
      rescue => e
        warn "Garmin: timezone resolution failed for #{activity_id}: #{e.message}"
        nil
      end

      # Extract first valid GPS coordinate (in degrees) from L2 file.
      # FIT records use positionLat/positionLong keys (already in degrees).
      def first_gps_from_l2(activity_id)
        l2_path = std_path(activity_id)
        return [nil, nil] unless File.exist?(l2_path)

        l2 = JSON.parse(File.read(l2_path))
        return [nil, nil] unless l2.is_a?(Array) && l2.any?

        first = l2.find { |r|
          lat = r["positionLat"]
          lng = r["positionLong"]
          lat && lng && lat.to_f != 0.0 && lng.to_f != 0.0
        }
        return [nil, nil] unless first

        [first["positionLat"].to_f, first["positionLong"].to_f]
      rescue JSON::ParserError
        [nil, nil]
      end

      def source_prefix
        "garmin"
      end

      def build_attrs(detail, activity_id, type, polyline = nil)
        summary = detail["summaryDTO"] || {}

        start_t = parse_garmin_time(summary["startTimeGMT"])
        moving_time = summary["movingDuration"]&.to_i || summary["duration"]&.to_i
        elapsed_time = summary["elapsedDuration"]&.to_i || summary["duration"]&.to_i

        {
          run_id: "#{source_prefix}_#{activity_id}",
          name: detail["activityName"] || "Garmin Activity",
          distance: summary["distance"]&.to_f,
          moving_time: moving_time,
          elapsed_time: elapsed_time,
          sport_category: type,
          sport_type: type_str(detail["activityTypeDTO"]),
          start_date: start_t&.utc&.iso8601,
          start_date_local: start_t&.iso8601,
          location_country: detail["locationName"],
          summary_polyline: polyline,
          average_heartrate: summary["averageHR"]&.to_f,
          max_heartrate: summary["maxHR"]&.to_f,
          average_cadence: summary["avgCadence"]&.to_f,
          max_cadence: summary["maxCadence"]&.to_f,
          average_power: summary["avgPower"]&.to_f,
          max_power: summary["maxPower"]&.to_f,
          calories: summary["calories"]&.to_i,
          average_temperature: summary["avgTemperature"]&.to_f,
          average_speed: summary["averageSpeed"]&.to_f,
          elevation_gain: summary["elevationGain"]&.to_f,
          source: source_prefix
        }
      end

      def parse_garmin_time(time_str)
        return nil unless time_str
        t = Time.parse(time_str)
        t.utc? ? t : t.utc
      rescue
        nil
      end

      def type_str(val)
        return "" unless val
        val.is_a?(Hash) ? (val["typeKey"] || "").downcase : val.to_s.downcase
      end

      def map_type(activity_type)
        ts = type_str(activity_type)
        return "other" if ts.empty?
        case ts
        when /running/ then "run"
        when /cycling/, /biking/ then "ride"
        when /hiking/ then "hike"
        when /walking/ then "walk"
        when /swimming/ then "swim"
        when /skiing/, /snowboard/ then "ski"
        when /workout/, /strength/, /fitness/ then "workout"
        else "other"
        end
      end

      def save_tokens
        path = token_path
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless dir == "."
        File.write(path, JSON.pretty_generate({
          oauth1: {
            oauth_token: @oauth1_token.oauth_token,
            oauth_token_secret: @oauth1_token.oauth_token_secret,
            mfa_token: @oauth1_token.mfa_token,
            domain: @oauth1_token.domain || @domain
          },
          oauth2: @access_token
        }))
      rescue => e
        puts "Failed to save Garmin tokens: #{e.message}"
      end

      def load_tokens
        path = token_path
        return false unless File.exist?(path)

        data = JSON.parse(File.read(path))
        o1 = data["oauth1"]
        saved_domain = o1["domain"]
        @domain = saved_domain if saved_domain
        @oauth1_token = OpenStruct.new(
          oauth_token: o1["oauth_token"],
          oauth_token_secret: o1["oauth_token_secret"],
          mfa_token: o1["mfa_token"],
          domain: @domain
        )
        @access_token = data["oauth2"]
        @saved_expires_at = @access_token&.dig("expires_at")
        true
      rescue => e
        puts "Failed to load Garmin tokens: #{e.message}"
        false
      end

      def token_path
        @config["token_path"] || File.join("data", "cache", "garmin_#{@domain.tr(".", "_")}_tokens.json")
      end

      # ── L1/L2 pipeline ──────────────────────────────────────────

      FIT_EPOCH = 631_065_600

      def raw_path(platform_id)
        File.join(raw_dir, "#{platform_id}.fit")
      end

      # Garmin API 返回两种格式:
      #   OAuth1 路径 (garmin.cn) → 字符串 (Google Polyline 编码)
      #   DI OAuth2 路径 (garmin.com) → 坐标对象数组 [{lat, lon, time, speed, ...}, ...]
      # Array 需编码为 Polyline 字符串再入库。
      def fetch_summary_polyline(activity_id)
        gps = api_get("/activity-service/activity/#{activity_id}/details")
        polyline = gps&.dig("geoPolylineDTO", "polyline")

        if polyline.is_a?(Array)
          points = polyline.map { |pt| [pt["lat"], pt["lon"]] }
          Geo::Polyline.encode(points) if points.size >= 2
        else
          polyline
        end
      rescue => e
        puts "Warning: failed to encode polyline for #{activity_id}: #{e.message}"
        nil
      end

      def download_fit_raw(activity_id)
        uri = URI("#{connectapi_base}/download-service/files/activity/#{activity_id}")
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@access_token.fetch("access_token")}"
        req["User-Agent"] = "GCM-iOS-5.22.1.4"
        resp = retry_on_429 { send_http(uri, req) }
        return false unless resp.code.to_i == 200

        tmp = "#{raw_path(activity_id)}.tmp"
        dir = raw_dir
        FileUtils.mkdir_p(dir)

        zip_data = resp.body
        fit_data = nil
        Zip::File.open_buffer(zip_data) do |zip|
          entry = zip.entries.first
          fit_data = entry.get_input_stream.read if entry
        end

        return false unless fit_data

        File.write(tmp, fit_data, mode: "wb")
        File.rename(tmp, raw_path(activity_id))
        true
      rescue => e
        puts "Failed to download FIT for #{activity_id}: #{e.message}"
        false
      end

      def fit_to_l2(activity_id)
        fit_path = raw_path(activity_id)
        return nil unless File.exist?(fit_path)

        records = FIT::Decoder.decode(fit_path)
        return nil if records.empty?

        records.map do |r|
          lat = r["positionLat"]
          lng = r["positionLong"]
          next unless lat && lng && lat != 0.0 && lng != 0.0

          ts = r["timestamp"]
          abs_ts = ts ? Time.at(FIT_EPOCH + ts).utc.xmlschema : nil

          {
            positionLat: lat,
            positionLong: lng,
            altitude: r["altitude"],
            heartRate: r["heartRate"],
            cadence: r["cadence"],
            power: r["power"],
            speed: r["speed"],
            timestamp: abs_ts,
            distance: r["distance"],
            temperature: r["temperature"]
          }.compact
        end.compact
      rescue => e
        puts "Failed to decode FIT for #{activity_id}: #{e.message}"
        nil
      end

      def write_standardized_json(l2, activity_id)
        return unless l2

        dir = std_dir
        FileUtils.mkdir_p(dir)
        tmp = File.join(dir, ".#{activity_id}.json.tmp")
        File.write(tmp, JSON.generate(l2))
        File.rename(tmp, std_path(activity_id))
      end
    end
  end
end

require_relative "base"
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
require "open3"

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

      def call
        if @domain == "garmin.com"
          return 0 if (@email.to_s.empty? || @password.to_s.empty?) && !File.exist?(di_token_path)
        else
          return 0 if @email.to_s.empty? && @secret.to_s.empty?
        end

        return 0 unless authenticate

        sync_activities
      end

      # 认证分发: garmin.com → DI OAuth2, garmin.cn → OAuth1
      def authenticate
        @oauth_consumer = fetch_oauth_consumer
        if @domain == "garmin.com"
          authenticate_di
        else
          authenticate_oauth1
        end
      end

      def authenticate_di
        if load_di_tokens
          return true if access_token_valid?
          begin
            return true if di_refresh
          rescue AuthError
            remove_stale_di_tokens
          end
        end

        return false if @email.to_s.empty? || @password.to_s.empty?

        if (token = strategy_a_login)
          @access_token = token
          save_di_tokens
          return true if verify_access_token
        end

        if (token = strategy_b_login)
          @access_token = token
          save_di_tokens
          return true if verify_access_token
        end

        false
      end

      def authenticate_oauth1
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

      private

      # -- DI OAuth2 methods (garmin.com) --

      def di_auth_base
        "https://diauth.#{@domain}"
      end

      def di_token_path
        @config["di_token_path"] || File.join("data", "cache", "garmin_#{@domain.tr(".", "_")}_tokens.json")
      end

      def load_di_tokens
        path = di_token_path
        return false unless File.exist?(path)

        data = JSON.parse(File.read(path))
        @access_token = data
        true
      rescue => e
        puts "Failed to load Garmin DI tokens: #{e.message}"
        false
      end

      def save_di_tokens
        return unless @access_token&.dig("access_token")

        path = di_token_path
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)
        File.write(path, JSON.pretty_generate(@access_token))
      rescue => e
        puts "Failed to save Garmin DI tokens: #{e.message}"
      end

      def remove_stale_di_tokens
        path = di_token_path
        File.delete(path) if File.exist?(path)
      rescue => e
        puts "Warning: failed to remove stale DI tokens: #{e.message}"
      end

      def di_refresh
        return false unless @access_token&.dig("refresh_token")

        uri = URI("#{di_auth_base}/di-oauth2-service/oauth/token")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          grant_type: "refresh_token",
          refresh_token: @access_token["refresh_token"]
        )

        resp = retry_on_429 { send_http(uri, req) }
        raise AuthError, "DI refresh error: #{resp.code}" unless resp.code.to_i == 200

        result = JSON.parse(resp.body)
        result["expires_at"] = Time.now.to_i + (result["expires_in"] || 64800).to_i
        if result["refresh_token_expires_in"]
          result["refresh_token_expires_at"] = Time.now.to_i + result["refresh_token_expires_in"].to_i
        end
        @access_token = result
        save_di_tokens
        true
      end

      def strategy_a_login
        script = File.expand_path("../../../scripts/garmin_auth.py", __dir__)
        return nil unless File.exist?(script)

        stdout, stderr, status = Open3.capture3(
          {"GARMIN_EMAIL" => @email, "GARMIN_PASSWORD" => @password, "GARMIN_DOMAIN" => @domain},
          "python3", script
        )
        warn stderr unless stderr.empty?
        JSON.parse(stdout) if status.success?
      rescue => e
        puts "Strategy A (curl_cffi) failed: #{e.message}"
        nil
      end

      def strategy_b_login
        nil # Phase 3: subprocess Playwright
      end

      # -- OAuth1 methods (garmin_cn) --

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
      rescue
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
      rescue
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
        raise AuthError, "Garmin OAuth refresh failed: #{e.message}"
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
        start = 0
        limit = 100
        count = 0

        loop do
          activities = fetch_activity_list(start, limit)
          break if activities.nil? || activities.empty?

          activities.each do |act|
            type = map_type(act["activityType"])
            next if skip_type?(type)

            details = fetch_activity_detail(act["activityId"])
            next unless details

            attrs = build_attrs(details, act["activityId"], type)
            upsert_activity(attrs)
            count += 1
            report_progress(count)
          end

          start += limit
        end

        count
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

      def build_attrs(detail, activity_id, type)
        summary = detail["summaryDTO"] || {}
        act_data = detail["activityDTO"] || {}
        loc_data = detail["locationDTO"] || {}

        start_t = parse_garmin_time(summary["startTimeGMT"])
        moving_time = summary["movingDuration"]&.to_i || summary["duration"]&.to_i
        elapsed_time = summary["elapsedDuration"]&.to_i || summary["duration"]&.to_i

        {
          run_id: "garmin_#{activity_id}",
          name: act_data["activityName"] || "Garmin Activity",
          distance: summary["distance"]&.to_f,
          moving_time: moving_time,
          elapsed_time: elapsed_time,
          sport_category: type,
          sport_type: (act_data["activityType"] || "").downcase,
          start_date: start_t&.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: start_t&.strftime("%Y-%m-%d %H:%M:%S"),
          location_country: loc_data["locationName"],
          average_heartrate: summary["averageHR"]&.to_f,
          average_speed: summary["averageSpeed"]&.to_f,
          elevation_gain: summary["elevationGain"]&.to_f,
          source: "garmin"
        }
      end

      def parse_garmin_time(time_str)
        return nil unless time_str
        Time.parse(time_str)
      rescue
        nil
      end

      def map_type(activity_type)
        return "other" unless activity_type
        case activity_type.downcase
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
        @config["token_path"] || File.expand_path("~/.workouts/garmin_tokens.json")
      end
    end
  end
end

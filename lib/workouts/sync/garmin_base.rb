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

module Workouts
  module Sync
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
      end

      def call
        return 0 if @email.nil? || @password.nil?

        return 0 unless authenticate

        sync_activities
      end

      def authenticate
        @oauth_consumer = fetch_oauth_consumer

        return true if @secret && parse_secret_string(@secret)
        return true if load_tokens && access_token_valid?
        return true if load_tokens && refresh_oauth2_via_oauth1

        ticket = sso_login
        @oauth1_token = fetch_oauth1_token(ticket)
        @access_token = exchange_oauth2
        save_tokens
        true
      rescue => e
        puts "Garmin auth error: #{e.message}"
        false
      end

      private

      def access_token_valid?
        return false unless @access_token

        expires_at = @access_token["expires_at"] || @saved_expires_at
        expires_at.nil? || Time.now.to_i < expires_at - 60
      end

      def parse_secret_string(secret)
        decoded = JSON.parse(Base64.strict_decode64(secret))
        o1 = decoded[0]
        o2 = decoded[1]

        @oauth1_token = OpenStruct.new(
          oauth_token: o1["oauth_token"],
          oauth_token_secret: o1["oauth_token_secret"],
          mfa_token: o1["mfa_token"],
          domain: o1["domain"] || @domain
        )
        @access_token = o2
        save_tokens
        true
      rescue => e
        puts "Invalid garth secret: #{e.message}"
        false
      end

      def refresh_oauth2_via_oauth1
        return false unless @oauth1_token&.oauth_token

        @access_token = exchange_oauth2
        @access_token["expires_at"] = Time.now.to_i + (@access_token["expires_in"] || 21600).to_i
        save_tokens
        true
      rescue
        false
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
        http = Net::HTTP.new(uri.host, uri.port, nil, nil, nil, nil)
        http.use_ssl = true
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
            mfa_token: @oauth1_token.mfa_token
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

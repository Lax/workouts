require_relative "igpsport_to_garmin"

module Workouts
  module Migrate
    class IGPSportToGarminCN < IGPSportToGarmin
      OAUTH_CONSUMER_URL = "https://thegarth.s3.amazonaws.com/oauth_consumer.json"

      private

      def authenticate
        path = token_path
        if File.exist?(path)
          data = JSON.parse(File.read(path))
          @access_token = data.dig("oauth2", "access_token")
          @saved_expires_at = data.dig("oauth2", "expires_at")

          return true unless token_expired?

          return true if refresh_cn_from_file(data)
        end

        secret = @config["secret"]
        if secret && !secret.empty?
          return true if parse_and_refresh_secret(secret)
        end

        puts "  Garmin CN: no valid token — run: bundle exec exe/workouts auth garmin_cn"
        false
      end

      def token_path
        @config["token_path"] || File.join("data", "cache", "garmin_garmin_cn_tokens.json")
      end

      def upload_map_dir
        File.join("data", "migrate", "igpsport_to_garmin_cn")
      end

      def refresh_cn_from_file(data)
        o1 = data["oauth1"]
        return false unless o1
        exchange_cn(data["oauth2"], o1)
      end

      def parse_and_refresh_secret(secret)
        decoded = JSON.parse(Base64.strict_decode64(secret))
        o1 = decoded[0]
        o2 = decoded[1]
        @access_token = o2["access_token"]
        @saved_expires_at = o2["expires_at"]

        return true unless token_expired?

        exchange_cn(o2, o1)
      rescue => e
        puts "  Garmin CN secret parse failed: #{e.message}"
        false
      end

      def exchange_cn(_o2_data, o1_data)
        oauth_consumer = fetch_oauth_consumer
        return false unless oauth_consumer

        saved_domain = o1_data["domain"]
        @domain = saved_domain if saved_domain

        token = OpenStruct.new(
          oauth_token: o1_data["oauth_token"],
          oauth_token_secret: o1_data["oauth_token_secret"],
          mfa_token: o1_data["mfa_token"],
          domain: @domain
        )

        new_o2 = do_oauth2_exchange(oauth_consumer, token)
        return false unless new_o2

        @access_token = new_o2["access_token"]
        @saved_expires_at = new_o2["expires_at"]
        save_cn_token(o1_data, new_o2)
        true
      rescue => e
        puts "  Garmin CN OAuth refresh failed: #{e.message}"
        false
      end

      def fetch_oauth_consumer
        resp = Faraday.get(OAUTH_CONSUMER_URL)
        JSON.parse(resp.body)
      rescue => e
        puts "  Failed to fetch OAuth consumer: #{e.message}"
        nil
      end

      def do_oauth2_exchange(consumer, oauth1_token)
        url = "https://connectapi.#{@domain}/oauth-service/oauth/exchange/user/2.0"

        oauth_consumer = OAuth::Consumer.new(
          consumer["consumer_key"], consumer["consumer_secret"],
          site: "https://connectapi.#{@domain}",
          scheme: :header, signature_method: "HMAC-SHA1"
        )

        token = OAuth::Token.new(oauth1_token.oauth_token, oauth1_token.oauth_token_secret)
        req = Net::HTTP::Post.new(URI(url))
        req["User-Agent"] = "com.garmin.android.apps.connectmobile"
        req["Content-Type"] = "application/x-www-form-urlencoded"
        body_params = { audience: "GARMIN_CONNECT_MOBILE_ANDROID_DI" }
        body_params[:mfa_token] = oauth1_token.mfa_token if oauth1_token.mfa_token
        req.body = URI.encode_www_form(body_params)
        oauth_consumer.sign!(req, token)

        resp = send_http(URI(url), req)
        return nil unless resp.code.to_i == 200

        result = JSON.parse(resp.body)
        result["expires_at"] = Time.now.to_i + (result["expires_in"] || 21600).to_i
        result
      end

      def save_cn_token(o1_data, o2_data)
        path = token_path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate({ oauth1: o1_data, oauth2: o2_data }))
      end
    end
  end
end

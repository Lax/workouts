require_relative "garmin_base"
require "open3"

module Workouts
  module Sync
    class GarminBaseDI < GarminBase
      def authenticate
        @oauth_consumer = fetch_oauth_consumer

        if load_tokens
          return true if access_token_valid?
          begin
            return true if refresh_token
          rescue AuthError
            remove_stale_tokens
          end
        end

        if load_seed_token
          return true if access_token_valid?
          begin
            return true if refresh_token
          rescue AuthError
            @access_token = nil
          end
        end

        return false if @email.to_s.empty? || @password.to_s.empty?

        if (token = strategy_a_login)
          @access_token = token
          save_tokens
          return true if verify_access_token
        end

        if (token = strategy_b_login)
          @access_token = token
          save_tokens
          return true if verify_access_token
        end

        false
      end

      def call
        return 0 if (@email.to_s.empty? || @password.to_s.empty?) && !File.exist?(token_path)

        return 0 unless authenticate

        sync_activities
      end

      private

      def auth_base
        "https://diauth.#{@domain}"
      end

      def load_tokens
        path = token_path
        return false unless File.exist?(path)

        data = JSON.parse(File.read(path))
        @access_token = data
        true
      rescue => e
        puts "Failed to load Garmin tokens: #{e.message}"
        false
      end

      def save_tokens
        return unless @access_token&.dig("access_token")

        path = token_path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(@access_token))
      rescue => e
        puts "Failed to save Garmin tokens: #{e.message}"
      end

      def remove_stale_tokens
        path = token_path
        File.delete(path) if File.exist?(path)
      rescue => e
        puts "Warning: failed to remove stale tokens: #{e.message}"
      end

      def load_seed_token
        seed = @config["refresh_token"]
        return false unless seed && !seed.empty?

        decoded = JSON.parse(Base64.strict_decode64(seed))
        @access_token = decoded
        save_tokens
        true
      rescue => e
        false
      end

      def refresh_token
        return false unless @access_token&.dig("refresh_token")

        uri = URI("#{auth_base}/di-oauth2-service/oauth/token")
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
        save_tokens
        true
      end

      def strategy_a_login
        script = File.expand_path("../../../scripts/garmin_auth.py", __dir__)
        return nil unless File.exist?(script)

        stdout, stderr, status = Open3.capture3(
          {"SYNC__GARMIN__EMAIL" => @email, "SYNC__GARMIN__PASSWORD" => @password, "SYNC__GARMIN__DOMAIN" => @domain},
          "python3", script
        )
        warn stderr unless stderr.empty?
        JSON.parse(stdout) if status.success?
      rescue => e
        puts "Strategy A (curl_cffi) failed: #{e.message}"
        nil
      end

      def strategy_b_login
        script = File.expand_path("../../../scripts/garmin_auth_playwright.py", __dir__)
        return nil unless File.exist?(script)

        stdout, stderr, status = Open3.capture3(
          {"SYNC__GARMIN__EMAIL" => @email, "SYNC__GARMIN__PASSWORD" => @password, "SYNC__GARMIN__DOMAIN" => @domain},
          "python3", script
        )
        warn stderr unless stderr.empty?
        JSON.parse(stdout) if status.success?
      rescue => e
        puts "Strategy B (Playwright) failed: #{e.message}"
        nil
      end
    end
  end
end

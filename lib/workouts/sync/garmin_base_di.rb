require_relative "garmin_base"
require "open3"

module Workouts
  module Sync
    class GarminBaseDI < GarminBase
      DI_CLIENT_IDS = %w[
        GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2
        GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4
        GARMIN_CONNECT_MOBILE_ANDROID_DI
      ].freeze

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

        if load_auth_seed
          return true if access_token_valid?
          begin
            return true if refresh_token
          rescue AuthError
            @access_token = nil
          end
        end

        puts "Garmin: no valid DI token found"
        puts "  First time: ./scripts/garmin_auth_local.sh"
        puts "  Refresh:    ./scripts/garmin_auth_local.sh --sync"
        false
      end

      def call
        if @config["auth_seed"].to_s.empty? && !File.exist?(token_path)
          puts "Garmin: auth_seed not configured and no cached token"
          puts "  Run: ./scripts/garmin_auth_local.sh"
          return 0
        end

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

      def load_auth_seed
        seed = @config["auth_seed"]
        return false unless seed && !seed.empty?

        decoded = JSON.parse(Base64.strict_decode64(seed))
        @access_token = decoded
        save_tokens
        true
      rescue JSON::ParserError
        puts "Garmin: auth_seed decode failed — invalid Base64 or JSON"
        puts "  Fix: ./scripts/garmin_auth_local.sh --sync"
        false
      rescue => e
        puts "Garmin: auth_seed error: #{e.message}"
        false
      end

      def refresh_token
        return false unless @access_token&.dig("refresh_token")

        client_id = @access_token["di_client_id"] || DI_CLIENT_IDS.first
        basic = Base64.strict_encode64("#{client_id}:")

        uri = URI("#{auth_base}/di-oauth2-service/oauth/token")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Basic #{basic}"
        req["Content-Type"] = "application/x-www-form-urlencoded"
        req["Cache-Control"] = "no-cache"
        req["User-Agent"] = "GCM-Android-5.23"
        req.body = URI.encode_www_form(
          grant_type: "refresh_token",
          client_id: client_id,
          refresh_token: @access_token["refresh_token"]
        )

        resp = retry_on_429 { send_http(uri, req) }
        unless resp.code.to_i == 200
          msg = "DI refresh error: #{resp.code}"
          if resp.code.to_i == 400
            msg += " — refresh_token expired across rotation"
            msg += ", re-run: scripts/garmin_auth_local.sh"
          elsif resp.code.to_i == 401
            msg += " — DI client_id rotated by Garmin"
            msg += ", re-run: scripts/garmin_auth_local.sh"
          end
          raise AuthError, msg
        end

        result = JSON.parse(resp.body)
        result["expires_at"] = Time.now.to_i + (result["expires_in"] || 64800).to_i
        if result["refresh_token_expires_in"]
          result["refresh_token_expires_at"] = Time.now.to_i + result["refresh_token_expires_in"].to_i
        end
        @access_token = result
        save_tokens
        true
      end

      # @deprecated Kept for local script reference only.
      # email+password SSO strategies are not called by `authenticate`
      # because garmin.com DI auth requires MFA, handled by
      # scripts/garmin_auth_local.sh outside Ruby.
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

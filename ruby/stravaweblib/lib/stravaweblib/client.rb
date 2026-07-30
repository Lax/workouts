require "faraday"
require "faraday-cookie_jar"
require "http/cookie_jar"
require "base64"
require "json"
require "time"
require "fileutils"
require "uri"

module StravaWebLib
  BASE_URL = "https://www.strava.com".freeze

  VALID_FORMATS = %i[original tcx gpx].freeze
  EXPORT_URLS = {
    original: "/activities/%s/export_original",
    tcx: "/activities/%s/export_tcx",
    gpx: "/activities/%s/export_gpx"
  }.freeze

  FORMAT_EXTS = {
    "fit" => :fit,
    "tcx" => :tcx,
    "gpx" => :gpx,
    "json" => :json
  }.freeze

  ExportResult = Data.define(:filename, :content, :format)

  class Client
    AUTH_HELP = "Set sync.strava.web_auth.jwt in config.yml — see docs/strava-web-auth.md".freeze

    def initialize(jwt: nil, auth_seed: nil, cookie_path: nil)
      @cookie_path = cookie_path
      @jar = HTTP::CookieJar.new

      load_cookies

      jwt ||= decode_auth_seed(auth_seed) if auth_seed

      explicit = jwt || (auth_seed && !auth_seed.to_s.strip.empty?)

      if explicit
        login_with_jwt(jwt)
      elsif authenticated?
        return
      else
        raise AuthError, "no web session — set jwt or auth_seed\n#{AUTH_HELP}"
      end

      save_cookies
    end

    def authenticated?
      return false if @jar.cookies(URI(BASE_URL)).empty?

      resp = build_session.get("/me")
      resp.status == 302
    rescue
      false
    end

    def export(activity_id, format: :original)
      raise ArgumentError, "unknown format: #{format.inspect}" unless VALID_FORMATS.include?(format)

      path = EXPORT_URLS[format.to_sym] % activity_id
      resp = build_session.get(path)

      unless resp.success?
        raise ExportError, "HTTP #{resp.status} for activity #{activity_id}"
      end

      filename = extract_filename(resp, activity_id, format)
      fmt = infer_format(filename, format)

      ExportResult.new(filename: filename, content: resp.body, format: fmt)
    end

    def persist_cookies!
      save_cookies
    end

    private

    def build_session
      Faraday.new(url: BASE_URL) do |f|
        f.use :cookie_jar, jar: @jar
        f.headers["User-Agent"] = "stravaweblib/#{VERSION}"
        f.headers["Accept"] = "*/*"
        f.options.timeout = 30
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end

    def load_cookies
      return unless @cookie_path && File.exist?(@cookie_path)
      @jar.load(@cookie_path, :yaml, session: true)
    rescue
      begin
        FileUtils.rm_f(@cookie_path)
      rescue
        nil
      end
    end

    def save_cookies
      return unless @cookie_path
      FileUtils.mkdir_p(File.dirname(@cookie_path))
      @jar.save(@cookie_path, :yaml, session: true)
    end

    def decode_auth_seed(seed)
      return nil if seed.to_s.strip.empty?

      Base64.strict_decode64(seed)
    rescue ArgumentError
      seed.to_s.strip
    end

    def login_with_jwt(jwt)
      jwt = jwt.to_s.strip
      raise AuthError, "jwt is empty" if jwt.empty?

      parts = jwt.split(".")
      raise AuthError, "invalid JWT (expected 3 parts, got #{parts.length})" unless parts.length == 3

      payload = parts[1]
      payload += "=" * (4 - payload.length % 4) if payload.length % 4 != 0

      begin
        data = JSON.parse(Base64.decode64(payload))
      rescue => e
        raise AuthError, "JWT payload decode failed: #{e.message}"
      end

      athlete_id = data["sub"].to_s
      raise AuthError, "JWT missing 'sub' claim" if athlete_id.empty?

      exp = data["exp"]
      if exp && exp.is_a?(Numeric) && Time.at(exp) < Time.now
        raise AuthError, "JWT expired at #{Time.at(exp)} — re-run local OTP login\n#{AUTH_HELP}"
      end

      URI(BASE_URL)
      @jar << HTTP::Cookie.new(
        "strava_remember_id", athlete_id,
        domain: ".strava.com", path: "/", secure: true,
        max_age: 365 * 86400
      )
      @jar << HTTP::Cookie.new(
        "strava_remember_token", jwt,
        domain: ".strava.com", path: "/", secure: true,
        max_age: 365 * 86400
      )

      begin
        resp = build_session.get("/me")
      rescue Faraday::Error => e
        raise AuthError, "network error verifying session: #{e.message}\n#{AUTH_HELP}"
      end
      unless resp.status == 302
        raise AuthError, "JWT session verification failed (HTTP #{resp.status})\n#{AUTH_HELP}"
      end
    end

    def extract_filename(resp, activity_id, format)
      cd = resp.headers["Content-Disposition"].to_s

      if (m = cd.match(/filename\*=UTF-8''([^;"]+)/))
        URI.decode_www_form_component(m[1])
      elsif (m = cd.match(/filename="([^"]+)"/))
        m[1]
      elsif (m = cd.match(/filename=([^;\s]+)/))
        m[1]
      else
        ext = (format == :original) ? "dat" : format.to_s
        "#{activity_id}.#{ext}"
      end
    end

    def infer_format(filename, source_format)
      ext = File.extname(filename).delete(".").downcase
      FORMAT_EXTS[ext] || source_format
    end
  end
end

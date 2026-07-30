require "thor"
require "stravaweblib"

module Workouts
  class StravaCLI < Thor
    class_option :config, type: :string, desc: "Path to config file", aliases: "-c"
    class_option :db, type: :string, desc: "Database path override"

    VALID_FORMATS = %w[original tcx gpx].freeze

    TOKEN_HELP = <<~HELP.freeze
      Token expired or invalid — generate a fresh one:
        1. Open  https://www.strava.com/login  → sign in with email + OTP
        2. F12 → Application → Cookies → https://www.strava.com
           Copy Value of:  strava_remember_token
        3. Local use:
             config/config.yml  →  sync.strava.web_auth.jwt: "<paste JWT>"
           CI use:
             echo -n "<paste JWT>" | base64 -w0 | gh secret set SYNC_STRAVA_WEB_AUTH_SEED -R Lax/workouts
      Docs: docs/strava-web-auth.md
      Token lifetime: ~30 days (JWT exp claim)
    HELP

    desc "fetch [ID ...]", "Download original files from Strava via web export"
    option :jwt, type: :string, desc: "JWT token for web auth (overrides cached session)"
    option :format, type: :string, default: "original",
      desc: "Export format: original, tcx, or gpx"
    option :output, type: :string, desc: "Output directory override",
      default: File.join("data", "raw", "strava")
    option :limit, type: :numeric, default: 10,
      desc: "Max activities per run (default: 10)"
    long_desc <<~DESC
      Download original activity files from Strava via the website export endpoint.

      With explicit IDs:
        workouts strava fetch 12345 67890

      Without IDs — reads the database to find Strava-sourced activities
      that don't yet have an original file:
        workouts strava fetch

      Auth via strava_remember_token JWT. See docs/strava-web-auth.md.
    DESC
    def fetch(*activity_ids)
      format = options[:format].to_s.downcase
      unless VALID_FORMATS.include?(format)
        raise ArgumentError, "unknown --format '#{format}' (valid: #{VALID_FORMATS.join(", ")})"
      end

      config = Workouts::Config.new(options[:config])
      strava_cfg = config.sync_config("strava")
      web_cfg = strava_cfg["web_auth"] || {}

      jwt = options[:jwt] || ENV["SYNC__STRAVA__WEB_AUTH__JWT"] || web_cfg["jwt"]
      auth_seed = ENV["SYNC__STRAVA__WEB_AUTH__AUTH_SEED"] || web_cfg["auth_seed"]

      output_dir = options[:output]
      FileUtils.mkdir_p(output_dir)
      cache_dir = File.join("data", "cache", "strava_downloads")
      FileUtils.mkdir_p(cache_dir)

      cookie_path = File.join("data", "cache", "strava_session.yml")

      if activity_ids.empty?
        begin
          db_path_val = options[:db] || config.db_path
          db = Workouts::DB::Connection.new(db_path_val).db
          all_ids = db[:activities]
            .where(source: "strava")
            .select_map(:run_id)
            .map { |rid| rid.sub("strava_", "") }
        rescue Sequel::DatabaseError => e
          say "DB error: #{e.message}", :red
          say "  Fix: rm -f #{db_path_val} && workouts db migrate", :yellow
          exit 1
        end

        if all_ids.empty?
          say "No Strava activities in database.", :yellow
          return
        end

        activity_ids = all_ids.reject do |id|
          File.exist?(File.join(output_dir, "#{id}.fit")) ||
            File.exist?(File.join(output_dir, "#{id}.gpx")) ||
            File.exist?(File.join(output_dir, "#{id}.tcx")) ||
            File.exist?(File.join(output_dir, "#{id}.json")) ||
            File.exist?(File.join(output_dir, "#{id}.dat"))
        end

        if activity_ids.empty?
          say "All #{all_ids.size} Strava activities already have original files.", :green
          return
        end

        total = activity_ids.size
        limit = options[:limit].to_i
        if limit > 0 && activity_ids.size > limit
          activity_ids = activity_ids.first(limit)
          say "Limited to #{limit} of #{total} pending", :cyan
        end

        say "Found #{all_ids.size} Strava activities in DB, #{total} without original files", :cyan
      end

      begin
        client = StravaWebLib::Client.new(
          jwt: jwt,
          auth_seed: auth_seed,
          cookie_path: cookie_path
        )
      rescue StravaWebLib::AuthError => e
        say "auth failed: #{e.message}", :red
        say TOKEN_HELP, :yellow
        exit 1
      rescue Faraday::Error => e
        say "auth failed: network — #{e.message}", :red
        exit 1
      end

      fmt_sym = format.to_sym
      success = 0
      skipped = 0
      failed = 0
      token_errors = 0

      activity_ids.each do |aid|
        existing = Dir.glob(File.join(output_dir, "#{aid}.*")).first

        if existing
          if validate_existing_file(existing)
            say "skip #{aid} (#{File.basename(existing)})", :yellow
            skipped += 1
            next
          else
            say "warn #{aid}: existing file invalid — re-downloading", :yellow
          end
        end

        begin
          result = client.export(aid, format: fmt_sym)

          unless result.content && !result.content.empty?
            say "error #{aid}: empty response", :red
            failed += 1
            next
          end

          unless valid_format?(result.content, result.format, fmt_sym)
            warn_html_error(result.content, aid)
            token_errors += 1
            failed += 1
            next
          end

          temp_path = File.join(cache_dir, result.filename)
          final_path = File.join(output_dir, result.filename)

          File.write(temp_path, result.content, mode: "wb")
          FileUtils.mv(temp_path, final_path)
          say "ok #{aid}  #{result.filename} (#{result.format})", :green
          success += 1
        rescue StravaWebLib::ExportError => e
          msg = e.message
          if msg.include?("HTTP 401") || msg.include?("HTTP 403")
            token_errors += 1
          end
          say "fail #{aid}: #{e.message}", :red
          failed += 1
        rescue Faraday::Error => e
          say "fail #{aid}: network — #{e.class}: #{e.message}", :red
          failed += 1
        end
      end

      client.persist_cookies!

      say ""
      say "fetch: #{success} downloaded, #{skipped} skipped, #{failed} failed", :blue
      say TOKEN_HELP, :yellow if token_errors > 0 && success == 0
    end

    private

    def valid_format?(content, format, requested_fmt)
      case format
      when :fit
        content.start_with?("\x0E\x10".b)
      when :tcx
        content.include?("TrainingCenterDatabase".b)
      when :gpx
        content.include?("<gpx".b)
      when :json
        JSON.parse(content)
        true
      else
        content.size > 0
      end
    rescue
      false
    end

    def warn_html_error(content, aid)
      head = content[0, 200].b
      if head.include?("<html") || head.include?("<!DOCTYPE")
        say "error #{aid}: Strava returned HTML (likely rate-limit or auth page) — #{content.length} bytes", :red
      else
        say "error #{aid}: unexpected content format — #{content[0, 80].b}", :red
      end
    end

    def validate_existing_file(path)
      return false unless File.exist?(path) && File.size(path) > 0

      content = File.read(path, mode: "rb", length: 4096)
      case File.extname(path).downcase
      when ".fit"
        content.start_with?("\x0E\x10".b)
      when ".tcx"
        content.include?("TrainingCenterDatabase".b)
      when ".gpx"
        content.include?("<gpx".b)
      when ".json"
        JSON.parse(content)
        true
      else
        content.size > 0
      end
    rescue
      false
    end
  end
end

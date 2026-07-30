require "fileutils"
require "json"
require "net/http"
require "uri"
require "faraday"
require "faraday/multipart"
require "nokogiri"

module Workouts
  module Migrate
    class IGPSportToGarmin
      JSON = ::JSON
      UPLOAD_PATH = "/upload-service/upload/"
      ACTIVITY_LIST_PATH = "/activitylist-service/activities/search/activities"
      SOURCE_SUFFIX = " [iGPSPORT]"

      CATEGORY_MAP = {
        "run" => "running", "ride" => "cycling", "walk" => "walking",
        "hike" => "hiking", "swim" => "swimming", "ski" => "skiing",
        "workout" => "other", "other" => "other"
      }.freeze

      def initialize(db:, config:, dry: false, since: nil, limit: nil)
        @db = db
        @config = config
        @dry = dry
        @since = since
        @limit = limit
        @domain = "garmin.com"
        @access_token = nil
        @count = 0
        @garmin_cache = {}
      end

      def call
        activities = load_igpsport_activities
        return 0 if activities.empty?
        return dry_run(activities) if @dry

        return 0 unless authenticate

        upload_map = load_upload_map

        activities.each do |act|
          run_id = act[:run_id]

          if upload_map["uploads"][run_id]
            puts "  #{run_id}: already uploaded (L1)"
            next
          end

          date_key = act[:start_date].to_s[0, 10]
          cached = fetch_garmin_activities(date_key)
          match = find_name_suffix_match(cached)
          if match
            upload_map["uploads"][run_id] = {
              "garmin_activity_id" => match["activityId"].to_s,
              "uploaded_at" => Time.now.utc.xmlschema,
              "matched_by" => "name_suffix"
            }
            save_upload_map(upload_map)
            puts "  #{run_id}: matched existing Garmin activity #{match["activityId"]} (L2)"
            next
          end

          result = upload_activity(act, run_id)
          if result
            upload_map["uploads"][run_id] = result
            save_upload_map(upload_map)
            @count += 1
            puts "  #{run_id}: uploaded OK → Garmin ID #{result["garmin_activity_id"]}"
          else
            puts "  #{run_id}: upload failed"
          end
        end

        @count
      end

      private

      def load_igpsport_activities
        ds = @db[:activities].where(source: "igpsport").order(Sequel.desc(:start_date))
        ds = ds.where(Sequel.lit("start_date >= ?", @since)) if @since
        ds = ds.limit(@limit) if @limit&.positive?
        ds.all
      end

      def dry_run(activities)
        puts "Activities to upload (#{activities.size}):"
        activities.each do |act|
          puts "  #{act[:run_id]}  #{act[:start_date]}  #{act[:name]}  #{act[:sport_category]}"
        end
        activities.size
      end

      def upload_activity(act, run_id)
        id = run_id.sub("igpsport_", "")
        fit_path = raw_igpsport_path(id)

        if File.exist?(fit_path)
          result = upload_fit(fit_path, act)
          return result if result
          puts "  FIT upload failed, falling back to GPX..."
        end

        l2 = load_l2_json(id)
        return nil unless l2

        gpx_xml = build_gpx(act, l2)
        upload_gpx(gpx_xml, act)
      end

      def upload_fit(file_path, act)
        filename = File.basename(file_path)
        url = upload_url
        resp = multipart_post(url, file_path, "application/octet-stream", filename)
        parse_upload_response(resp)
      end

      def upload_gpx(gpx_xml, act)
        tmp = File.join(Dir.tmpdir, ".igp_garmin_#{act[:run_id]}.gpx")
        File.write(tmp, gpx_xml)
        url = upload_url
        resp = multipart_post(url, tmp, "application/gpx+xml", "#{act[:run_id]}.gpx")
        File.delete(tmp)
        parse_upload_response(resp)
      end

      def multipart_post(url, file_path, content_type, filename)
        Faraday.post(url) do |req|
          req.headers["Authorization"] = "Bearer #{@access_token}"
          req.headers["User-Agent"] = "GCM-iOS-5.22.1.4"
          req.body = Faraday::UploadIO.new(file_path, content_type, filename)
        end
      end

      def parse_upload_response(resp)
        return nil unless resp.status == 200

        body = JSON.parse(resp.body)
        result = body.dig("detailedImportResult")
        return nil unless result

        successes = result["successes"]
        return nil if successes.nil? || successes.empty?

        garmin_id = successes.first["internalId"] || successes.first["externalId"]
        return nil unless garmin_id

        {
          "garmin_activity_id" => garmin_id.to_s,
          "uploaded_at" => Time.now.utc.xmlschema,
          "format" => "fit"
        }
      rescue JSON::ParserError
        nil
      end

      def upload_url
        "https://connectapi.#{@domain}#{UPLOAD_PATH}"
      end

      # ── Auth (delegated to shared helper) ─────────────────────

      def authenticate
        result = Auth::GarminToken.for_intl(@config)
        return false unless result

        @access_token = result[:access_token]
        @domain = result[:domain]
        true
      end

      # ── L2 Dedup ──────────────────────────────────────────────

      def fetch_garmin_activities(date_str)
        return @garmin_cache[date_str] if @garmin_cache.key?(date_str)

        all = []
        start = 0
        limit = 100
        loop do
          resp = api_get("#{ACTIVITY_LIST_PATH}?start=#{start}&limit=#{limit}")
          break unless resp

          days = resp.select { |a| (a["startTimeGMT"] || "")[0, 10] == date_str }
          all.concat(days)
          start += limit
          break if resp.size < limit
        end

        @garmin_cache[date_str] = all
        all
      end

      def api_get(path)
        uri = URI("https://connectapi.#{@domain}#{path}")
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@access_token}"
        req["User-Agent"] = "GCM-iOS-5.22.1.4"

        resp = send_http(uri, req)
        return nil unless resp.code.to_i == 200

        JSON.parse(resp.body)
      end

      def find_name_suffix_match(activities)
        return nil if activities.empty?

        suffix_down = SOURCE_SUFFIX.downcase
        activities.find { |a| (a["activityName"] || "").downcase.end_with?(suffix_down) }
      end

      # ── GPX Builder ───────────────────────────────────────────

      def build_gpx(act, l2_records)
        name = esc(act[:name] || "Activity") + SOURCE_SUFFIX
        type = CATEGORY_MAP[act[:sport_category]] || "other"
        run_id = act[:run_id]
        start_t = format_time(act[:start_date])

        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.gpx(
            :version => "1.1",
            :creator => "Workouts CLI",
            :xmlns => "http://www.topografix.com/GPX/1/1",
            "xmlns:gpxtpx" => "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
          ) do
            xml.metadata do
              xml.name_ name
              xml.desc "Imported from iGPSPORT. Source: #{run_id}"
              xml.time start_t if start_t
              xml.link(href: "https://igpsport.com/activity/#{run_id}") do
                xml.text_ run_id
              end
            end
            xml.trk do
              xml.name_ name
              xml.src run_id
              xml.desc "Imported from iGPSPORT. Source: #{run_id}"
              xml.type_ type
              xml.trkseg do
                l2_records.each do |pt|
                  lat = pt["positionLat"] || pt["latitude"]
                  lng = pt["positionLong"] || pt["longitude"]
                  next unless lat && lng

                  ts_raw = pt["timestamp"]
                  time_val = case ts_raw
                  when String then ts_raw
                  when Numeric
                    fit_epoch = Time.new(1989, 12, 31, 0, 0, 0, "+00:00").to_i
                    begin
                      Time.at(fit_epoch + ts_raw).utc.xmlschema
                    rescue
                      nil
                    end
                  end

                  xml.trkpt(lat: fmt_coord(lat), lon: fmt_coord(lng)) do
                    xml.ele pt["altitude"] if pt["altitude"]
                    xml.time time_val if time_val
                    if pt["heartRate"] || pt["cadence"] || pt["power"] || pt["temperature"]
                      xml.extensions do
                        xml.parent.namespace = xml.parent.document.root.add_namespace_definition(
                          "gpxtpx", "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
                        )
                        xml["gpxtpx"].TrackPointExtension do
                          xml["gpxtpx"].hr pt["heartRate"].to_i if pt["heartRate"]
                          xml["gpxtpx"].cad pt["cadence"].to_i if pt["cadence"]
                          xml["gpxtpx"].watts pt["power"].to_i if pt["power"]
                          xml["gpxtpx"].temp pt["temperature"].to_i if pt["temperature"]
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        builder.to_xml
      end

      def raw_igpsport_path(ride_id)
        File.join("data", "raw", "igpsport", "#{ride_id}.fit")
      end

      def load_l2_json(ride_id)
        path = File.join("data", "std", "igpsport", "#{ride_id}.json")
        return nil unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end

      # ── Upload Map (L1 Dedup) ─────────────────────────────────

      def upload_map_dir
        File.join("data", "migrate", "igpsport_to_garmin")
      end

      def upload_map_path
        File.join(upload_map_dir, "uploads.json")
      end

      def load_upload_map
        path = upload_map_path
        return {"uploads" => {}} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {"uploads" => {}}
      end

      def save_upload_map(map)
        dir = upload_map_dir
        FileUtils.mkdir_p(dir)
        tmp = "#{upload_map_path}.tmp"
        File.write(tmp, JSON.pretty_generate(map))
        File.rename(tmp, upload_map_path)
      end

      # ── Helpers ───────────────────────────────────────────────

      def format_time(t_str)
        return nil unless t_str
        begin
          Time.parse(t_str).utc.xmlschema
        rescue
          nil
        end
      end

      def esc(s)
        s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
          .gsub("'", "&apos;").gsub('"', "&quot;")
      end

      def fmt_coord(v)
        format("%.6f", v.to_f)
      end

      def send_http(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 30
        http.read_timeout = 60
        http.start { |h| h.request(request) }
      end
    end
  end
end

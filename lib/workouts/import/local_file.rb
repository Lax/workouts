require "digest"
require "fileutils"
require "json"
require "nokogiri"
require "securerandom"

module Workouts
  module Import
    class LocalFile < Sync::Base
      IMPORT_DIRS = {
        "gpx" => "data/import/gpx",
        "fit" => "data/import/fit",
        "tcx" => "data/import/tcx"
      }.freeze

      SUPPORTED_EXTENSIONS = %w[.gpx .fit .tcx].freeze

      NS_GPX = { gpx: "http://www.topografix.com/GPX/1/1" }.freeze
      NS_TCX = { tcx: "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" }.freeze

      def initialize(config:, db:, activity_filter: nil, privacy: nil, time_budget: nil, sources: nil, sport_override: nil)
        super(config:, db:, activity_filter:, privacy:, time_budget:)
        @sources = sources
        @sport_override = sport_override
      end

      def call
        return 0 unless authenticate

        total_imported = 0
        @sources.each do |source|
          dir = IMPORT_DIRS[source]
          next unless dir && File.directory?(dir)

          files = Dir.glob(File.join(dir, "*"), File::FNM_CASEFOLD)
                     .select { |f| SUPPORTED_EXTENSIONS.include?(File.extname(f).downcase) && File.file?(f) }

          total_imported += process_files(files, source)
        end

        total_imported
      end

      def authenticate
        true
      end

      def pending_ids
        []
      end

      def source_label
        "LocalFile"
      end

      def raw_dir_for(source)
        File.join("data", "raw", source)
      end

      def std_dir_for(source)
        File.join("data", "std", source)
      end

      private

      def process_files(files, source)
        total_activities = 0
        total = files.size

        files.each_with_index do |file_path, idx|
          break if time_expired? && total_activities.positive?

          result = process_single_file(file_path, source)
          if result
            activity_count = result[:activity_count] || 1
            total_activities += activity_count
            report_progress(idx + 1, total, "#{activity_count} act from #{File.basename(file_path)}")
          end
        end

        total_activities
      end

      def process_single_file(file_path, source)
        content = File.binread(file_path)
        sha = Digest::SHA256.hexdigest(content)
        platform_id = "#{source}_#{sha[0, 12]}"

        return nil if existing_run_id?(platform_id)

        ext = File.extname(file_path).downcase
        raw_source_dir = raw_dir_for(source)

        raw_path = File.join(raw_source_dir, "#{platform_id}#{ext}")
        FileUtils.mkdir_p(raw_source_dir)
        tmp = "#{raw_path}.tmp"
        File.binwrite(tmp, content)
        File.rename(tmp, raw_path)

        activities = parse_file(ext, content, file_path)
        return nil if activities.empty?

        l2_points = extract_l2_points(ext, content, file_path)

        imported = 0
        activities.each do |activity|
          activity[:source] = source
          activity[:run_id] = imported.zero? ? platform_id : "#{platform_id}_#{imported}"

          if source == "gpx" && @sport_override
            activity[:sport_category] = SportMapper.canonicalize(@sport_override)
          end

          if l2_points&.any?
            std_source_dir = std_dir_for(source)
            FileUtils.mkdir_p(std_source_dir)
            std_data = l2_points.map { |pt|
              h = { latitude: pt[0], longitude: pt[1] }
              h[:altitude] = pt[2] if pt[2]
              h[:timestamp] = pt[3]&.iso8601 if pt[3]
              h[:heart_rate] = pt[4] if pt[4]
              h
            }
            std_tmp = File.join(std_source_dir, ".#{activity[:run_id]}.json.tmp")
            std_final = File.join(std_source_dir, "#{activity[:run_id]}.json")
            File.write(std_tmp, JSON.generate(std_data))
            File.rename(std_tmp, std_final)

            coords = l2_points.map { |p| [p[0], p[1]] }
            activity[:summary_polyline] = Geo::Polyline.encode(coords)
          end

          upsert_activity(activity)
          imported += 1
        end

        { activity_count: imported }
      rescue => e
        $stderr.puts "LocalFile: error importing #{file_path}: #{e.message}"
        nil
      end

      def parse_file(ext, content, file_path)
        case ext
        when ".gpx"
          Workouts::Parser::GPX.new.call(content)
        when ".tcx"
          Workouts::Parser::TCX.new.call(content)
        when ".fit"
          Workouts::Parser::FIT.new.call(file_path)
        else
          []
        end
      end

      def extract_l2_points(ext, content, file_path)
        case ext
        when ".gpx"
          extract_gpx_points(content)
        when ".tcx"
          extract_tcx_points(content)
        when ".fit"
          extract_fit_points(file_path)
        else
          nil
        end
      end

      def extract_gpx_points(xml)
        doc = Nokogiri::XML(xml)
        doc.remove_namespaces!
        doc.xpath("//trkpt").filter_map do |pt|
          lat = pt["lat"]&.to_f
          lon = pt["lon"]&.to_f
          next unless lat && lon
          ele = pt.at_xpath("ele")&.text&.to_f
          time_str = pt.at_xpath("time")&.text
          time = parse_timestamp(time_str)
          hr = pt.at_xpath("extensions//hr")&.text&.to_f
          [lat, lon, ele, time, hr]
        end
      rescue => e
        $stderr.puts "LocalFile: GPX parse error: #{e.message}"
        nil
      end

      def extract_tcx_points(xml)
        doc = Nokogiri::XML(xml)
        doc.xpath("//tcx:Trackpoint", NS_TCX).filter_map do |tp|
          pos = tp.at_xpath("tcx:Position", NS_TCX)
          next unless pos
          lat = pos.at_xpath("tcx:LatitudeDegrees", NS_TCX)&.text&.to_f
          lon = pos.at_xpath("tcx:LongitudeDegrees", NS_TCX)&.text&.to_f
          next unless lat && lon
          ele = tp.at_xpath("tcx:AltitudeMeters", NS_TCX)&.text&.to_f
          time_str = tp.at_xpath("tcx:Time", NS_TCX)&.text
          time = parse_timestamp(time_str)
          hr = tp.at_xpath("tcx:HeartRateBpm/tcx:Value", NS_TCX)&.text&.to_f
          [lat, lon, ele, time, hr]
        end
      rescue => e
        $stderr.puts "LocalFile: TCX parse error: #{e.message}"
        nil
      end

      def extract_fit_points(file_path)
        records = Workouts::FIT::Decoder.decode(file_path)
        records.filter_map do |r|
          lat = r["positionLat"]
          lon = r["positionLong"]
          next unless lat && lon
          ts = r["timestamp"]
          time = ts.is_a?(Numeric) ? (Time.utc(1989, 12, 31) + ts) : (Time.parse(ts.to_s) rescue nil)
          [lat, lon, r["altitude"], time, r["heartRate"]]
        end
      rescue => e
        $stderr.puts "LocalFile: FIT decode error: #{e.message}"
        nil
      end

      def parse_timestamp(str)
        return nil unless str
        Time.parse(str)
      rescue ArgumentError
        nil
      end

      def existing_run_id?(platform_id)
        !@db[:activities].where(run_id: platform_id).empty?
      end
    end
  end
end

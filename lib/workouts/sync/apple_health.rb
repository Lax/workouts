require "digest"
require "fileutils"
require "nokogiri"
require "zip"
require_relative "base"

module Workouts
  module Sync
    class AppleHealth < Base
      SKIPPED_SOURCE_PATTERNS = [
        /\bStrava\b/i, /\bKeep\b/i, /\biGPSPORT\b/i,
        /\bXOSS\b/i, /\bXingZhe\b/i, /\bConnect\b/i
      ].freeze

      APPLE_WATCH_PATTERN = /Apple Watch/

      DEFAULT_ZIP_PATH = "data/import/apple_health/export.zip"

      HeartRateRecord = Struct.new(:time, :value, keyword_init: true)

      MIN_GPX_SPEED = 0.1

      def initialize(config:, db:, activity_filter: nil, privacy: nil, time_budget: nil)
        super
        @zip_path = @config["zip_path"] || DEFAULT_ZIP_PATH
        @heart_rate_index = nil
        @heart_rate_by_date = nil
      end

      def before_call
        return false unless File.exist?(@zip_path)
        super
      end

      def authenticate
        true
      end

      def call
        return 0 unless before_call
        return 0 unless authenticate
        ids = pending_ids
        return 0 if ids.nil? || ids.empty?

        total = ids.size
        processed = 0
        ids.each do |p|
          break if time_expired? && processed.positive?
          r = process_one(p)
          processed += 1 if r
          report_progress(processed, total, build_progress_info(r)) if r
        end

        processed
      end

      def pending_ids
        existing = existing_run_ids_set
        results = []
        hr_records = []
        zip = Zip::File.new(@zip_path)
        xml_entry = zip.find_entry("apple_health_export/export.xml")
        return results unless xml_entry

        io = xml_entry.get_input_stream
        buffer = ""
        in_workout = false

        io.each_line do |line|
          if line.include?("HKQuantityTypeIdentifierHeartRate") && APPLE_WATCH_PATTERN.match?(line)
            hr = parse_hr_line(line)
            hr_records << hr if hr
          end

          if !in_workout
            if line.include?("<Workout ")
              in_workout = true
              buffer = line
            end
          else
            buffer << line
            if line.include?("</Workout>")
              process_workout_chunk(buffer, existing, results)
              buffer = ""
              in_workout = false
            end
          end
        end

        @heart_rate_index = hr_records.sort_by(&:time)

        @heart_rate_by_date = {}
        @heart_rate_index.each do |hr|
          date_key = hr.time.strftime("%Y-%m-%d")
          @heart_rate_by_date[date_key] ||= []
          @heart_rate_by_date[date_key] << hr
        end

        results
      ensure
        zip&.close
        io&.close rescue nil
      end

      def process_one(pending)
        raw_xml = pending[:raw_xml]
        run_id = pending[:run_id]
        source_name = pending[:source_name]
        stats = pending[:stats]
        meta = pending[:meta]
        route_paths = pending[:route_paths]
        start_date = pending[:start_date]
        end_date = pending[:end_date]
        duration = pending[:duration]
        duration_unit = pending[:duration_unit]
        workout_type = pending[:workout_type]

        FileUtils.mkdir_p(raw_dir)
        tmp = File.join(raw_dir, ".#{run_id}.xml.tmp")
        final = File.join(raw_dir, "#{run_id}.xml")
        File.write(tmp, raw_xml)
        File.rename(tmp, final)

        hr_avg = nil
        hr_max = nil
        if @heart_rate_index&.any?
          hr_avg, hr_max = correlate_heart_rate(start_date, end_date)
        end

        l2_points = nil
        polyline = nil
        elevation_gain = nil

        if route_paths&.any?
          gpx_l1_path = File.join(raw_dir, "#{run_id}.gpx")
          unless File.exist?(gpx_l1_path)
            begin
              zip = Zip::File.new(@zip_path)
              route_paths.each do |gpx_path|
                normalized = gpx_path.sub(%r{^/?}, "apple_health_export/")
                entry = zip.find_entry(normalized)
                next unless entry
                data = entry.get_input_stream.read
                tmpp = File.join(raw_dir, ".#{run_id}.gpx.tmp")
                File.write(tmpp, data)
                File.rename(tmpp, gpx_l1_path)
                break
              end
            rescue => e
              $stderr.puts "AppleHealth: GPX extract error for #{run_id}: #{e.message}"
            ensure
              zip&.close
            end
          end

          l2_points = File.exist?(gpx_l1_path) ? parse_gpx_file(gpx_l1_path) : nil

          if l2_points&.any?
            FileUtils.mkdir_p(std_dir)
            std_data = l2_points.map { |pt|
              h = { latitude: pt[:lat], longitude: pt[:lng] }
              h[:altitude] = pt[:ele] if pt[:ele]
              h[:timestamp] = pt[:time] if pt[:time]
              h[:speed] = pt[:speed] if pt[:speed]
              h
            }
            tmp2 = File.join(std_dir, ".#{run_id}.json.tmp")
            final2 = File.join(std_dir, "#{run_id}.json")
            File.write(tmp2, JSON.generate(std_data))
            File.rename(tmp2, final2)

            coords = l2_points.map { |pt| [pt[:lat], pt[:lng]] }
            polyline = Geo::Polyline.encode(coords)
            elevation_gain = elevation_gain_from_points(l2_points)
          end
        end

        title = build_title(workout_type, start_date)
        attrs = build_attrs(source_name, run_id, stats, meta, polyline, elevation_gain,
                            workout_type, start_date, end_date, duration, duration_unit,
                            hr_avg, hr_max)
        attrs[:title] = title
        upsert_activity(attrs)
        attrs
      end

      def source_label
        "AppleHealth"
      end

      def raw_dir
        File.join("data", "raw", "apple_health")
      end

      def std_dir
        File.join("data", "std", "apple_health")
      end

      def raw_path(platform_id)
        File.join(raw_dir, "#{platform_id}.xml")
      end

      private

      def known_source?(source_name)
        return false unless source_name
        SKIPPED_SOURCE_PATTERNS.any? { |pattern| pattern.match?(source_name) }
      end

      def existing_run_ids_set
        @db[:activities].where(source: "apple_health").select_map(:run_id).map(&:to_s).to_set
      end

      def parse_hr_line(line)
        m = line.match(/startDate="([^"]+)".*?value="(\d+)"/)
        return nil unless m
        time = Time.parse(m[1]) rescue nil
        return nil unless time
        HeartRateRecord.new(time: time, value: m[2].to_i)
      end

      def correlate_heart_rate(start_date_str, end_date_str)
        start_t = Time.parse(start_date_str) rescue nil
        end_t = Time.parse(end_date_str) rescue nil
        return [nil, nil] unless start_t && end_t

        records = collect_hr_in_window(start_t, end_t)
        return [nil, nil] if records.empty?

        vals = records.map(&:value)
        avg = (vals.sum.to_f / vals.size).round(1)
        max = vals.max
        [avg, max]
      end

      def collect_hr_in_window(start_t, end_t)
        unless @heart_rate_by_date
          return [] unless @heart_rate_index&.any?
          lo = @heart_rate_index.bsearch_index { |hr| hr.time >= start_t }
          hi = @heart_rate_index.bsearch_index { |hr| hr.time > end_t }
          return [] unless lo
          slice = hi ? @heart_rate_index[lo...hi] : @heart_rate_index[lo..]
          return slice || []
        end

        results = []

        (start_t.to_date..end_t.to_date).each do |date|
          date_key = date.strftime("%Y-%m-%d")
          bucket = @heart_rate_by_date[date_key]
          if bucket&.any?
            lo = bucket.bsearch_index { |hr| hr.time >= start_t }
            hi = bucket.bsearch_index { |hr| hr.time > end_t }
            if lo
              slice = hi ? bucket[lo...hi] : bucket[lo..]
              results.concat(slice) if slice&.any?
            end
          end
        end

        results
      end

      def process_workout_chunk(raw_xml, existing_ids, results)
        doc = Nokogiri::XML("<root>#{raw_xml}</root>")
        workout = doc.at_xpath("//Workout")
        return unless workout

        source_name = workout["sourceName"]
        return if known_source?(source_name)

        workout_type = workout["workoutActivityType"]
        return unless workout_type

        start_date = workout["startDate"]
        end_date = workout["endDate"]
        return if start_date.nil? || end_date.nil?

        duration = workout["duration"]
        duration_unit = workout["durationUnit"] || "min"
        return if duration.nil?

        run_id = generate_run_id(source_name, start_date, end_date)
        return if existing_ids.include?("apple_health_#{run_id}")

        category = map_sport_type(workout_type)
        return if skip_type?(category)

        stats = extract_statistics(workout)
        meta = extract_metadata(workout)
        route_paths = extract_route_paths(workout)
        source_version = workout["sourceVersion"]

        results << {
          id: run_id,
          type: category,
          raw_xml: raw_xml,
          run_id: run_id,
          source_name: source_name,
          source_version: source_version,
          workout_type: workout_type,
          duration: duration,
          duration_unit: duration_unit,
          start_date: start_date,
          end_date: end_date,
          stats: stats,
          meta: meta,
          route_paths: route_paths
        }
      end

      def extract_statistics(workout)
        stats = {}
        workout.xpath("WorkoutStatistics").each do |stat|
          type = stat["type"]
          sum = stat["sum"]
          unit = stat["unit"]
          next unless type && sum
          stats[type] = { "sum" => sum, "unit" => unit }
        end
        stats
      end

      def extract_metadata(workout)
        meta = {}
        workout.xpath("MetadataEntry").each do |entry|
          key = entry["key"]
          value = entry["value"]
          meta[key] = value if key && value
        end
        meta
      end

      def extract_route_paths(workout)
        workout.xpath("WorkoutRoute/FileReference").filter_map do |ref|
          ref["path"]
        end
      end

      def parse_gpx_file(file_path)
        doc = Nokogiri::XML(File.read(file_path))
        doc.remove_namespaces!
        doc.xpath("//trkpt").filter_map do |pt|
          lat = pt["lat"]&.to_f
          lng = pt["lon"]&.to_f
          next unless lat && lng
          ele = pt.at_xpath("ele")&.text&.to_f
          time_str = pt.at_xpath("time")&.text
          ext = pt.at_xpath("extensions")
          speed = ext&.at_xpath("speed")&.text&.to_f
          speed = nil if speed && speed < MIN_GPX_SPEED
          { lat: lat, lng: lng, ele: ele, time: time_str, speed: speed }
        end
      rescue => e
        $stderr.puts "AppleHealth: GPX parse error for #{file_path}: #{e.message}"
        nil
      end

      def build_attrs(_source_name, run_id, stats, meta, polyline, elevation_gain,
                      workout_type, start_date, end_date, duration, duration_unit,
                      hr_avg = nil, hr_max = nil)
        distance = nil
        calories = nil

        cals_sum = 0.0
        stats.each do |type_str, data|
          if type_str.include?("Distance")
            distance = parse_distance(data["sum"], data["unit"])
          elsif type_str.include?("ActiveEnergyBurned") || type_str.include?("BasalEnergyBurned")
            cals_sum += data["sum"].to_f
          end
        end
        calories = cals_sum > 0 ? cals_sum.round : nil

        moving_time = parse_duration(duration, duration_unit)
        elapsed_time = compute_elapsed(start_date, end_date) || moving_time
        avg_speed = if distance && moving_time&.positive?
                      (distance.to_f / moving_time).round(2)
                    end

        attrs = {
          run_id: "apple_health_#{run_id}",
          name: display_name(workout_type, start_date),
          distance: distance,
          moving_time: moving_time,
          elapsed_time: elapsed_time,
          sport_category: map_sport_type(workout_type),
          sport_type: workout_type,
          start_date: format_datetime(start_date),
          start_date_local: meta["HKTimeZone"] ? format_datetime(start_date) : nil,
          summary_polyline: polyline,
          average_heartrate: hr_avg,
          max_heartrate: hr_max,
          average_speed: avg_speed,
          calories: calories,
          elevation_gain: elevation_gain&.round(1),
          average_temperature: parse_temperature(meta["HKWeatherTemperature"]),
          source: "apple_health"
        }

        attrs
      end

      def format_datetime(str)
        return nil unless str
        Time.parse(str).strftime("%Y-%m-%d %H:%M:%S") rescue str
      end

      def compute_elapsed(start_str, end_str)
        return nil unless start_str && end_str
        s = Time.parse(start_str) rescue nil
        e = Time.parse(end_str) rescue nil
        return nil unless s && e
        (e - s).round
      end

      def parse_duration(value, unit)
        v = value.to_f
        case unit.to_s.downcase
        when "min" then (v * 60).round
        when "sec" then v.round
        when "hour" then (v * 3600).round
        else (v * 60).round
        end
      end

      def parse_distance(value, unit)
        v = value.to_f
        case unit.to_s.downcase
        when "km" then (v * 1000).round(2)
        when "mi" then (v * 1609.344).round(2)
        when "m" then v.round(2)
        when "ft" then (v * 0.3048).round(2)
        else v.round(2)
        end
      end

      def parse_temperature(value)
        return nil unless value && !value.empty?
        m = value.match(/([\d.]+)\s*(deg[FC]|°[FC]|℃)/i)
        return nil unless m
        num = m[1].to_f
        unit = m[2].downcase
        if unit.start_with?("degf") || unit.start_with?("°f")
          ((num - 32) * 5.0 / 9.0).round(1)
        else
          num.round(1)
        end
      end

      def parse_humidity(value)
        return nil unless value && !value.empty?
        value.to_f / 100.0
      end

      def generate_run_id(source_name, start_date, end_date)
        Digest::MD5.hexdigest("#{source_name}|#{start_date}|#{end_date}")[0, 8]
      end

      def map_sport_type(workout_type)
        return "other" unless workout_type
        key = workout_type.sub(/\AHKWorkoutActivityType/, "")
        return "workout" if key.downcase.include?("strength")
        SportMapper.canonicalize(key)
      end

      def display_name(workout_type, _start_date)
        workout_type.sub(/\AHKWorkoutActivityType/, "")
      end

      def build_title(workout_type, start_date)
        label = workout_type.sub(/\AHKWorkoutActivityType/, "")
        date = start_date ? start_date[0..9] : nil
        date ? "#{date} · #{label}" : label
      end

      def elevation_gain_from_points(points)
        total = 0.0
        (1...points.length).each do |i|
          elev1 = points[i - 1][:ele] || 0.0
          elev2 = points[i][:ele] || 0.0
          gain = elev2 - elev1
          total += gain if gain > 0
        end
        total
      end
    end
  end
end

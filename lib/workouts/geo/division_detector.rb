require "json"
require "fileutils"
require_relative "reverse_geocode"

module Workouts
  module Geo
    class DivisionDetector
      KEEP_PLACEHOLDER = Workouts::Source::Keep::PLACEHOLDER_POLYLINE
      SAMPLE_INTERVAL_DEG = 0.01
      CACHE_DIR = "data/cache"
      POINT_CACHE_FILE = File.join(CACHE_DIR, "geo-point.jsonl")

      def initialize(db:, amap_key: nil, batch: 20, limit: nil, strategy: "proportional", time_budget: nil, dry_run: false)
        @db = db
        @geocoder = ReverseGeocode.new(amap_key: amap_key)
        @batch = batch
        @limit = limit
        @strategy = strategy
        @time_budget = time_budget
        @start_time = Time.now
        @dry_run = dry_run
        @processed = 0
        @skipped = 0
        @errors = 0
        @attempted = 0
        @total = 0
        FileUtils.mkdir_p(CACHE_DIR)
        load_caches
      end

      def run
        activities = pending_activities
        @total = activities.size
        $stdout.puts "Geo detection: #{@total} activities to process"
        activities.each_slice(@batch) do |batch|
          break if budget_exhausted?
          process_batch(batch)
          break if @limit && @processed >= @limit
        end
        print_summary
      end

      private

      def pending_activities
        dataset = @db[:activities]
          .where(Sequel.lit("summary_polyline IS NOT NULL"))
          .where(Sequel.lit("summary_polyline != ''"))
          .where(Sequel.lit("divisions IS NULL"))
          .order(Sequel.desc(:start_date))
        dataset = dataset.limit(@limit) if @limit
        dataset.all
      end

      def process_batch(batch)
        @db.transaction do
          batch.each do |activity|
            break if budget_exhausted? || (@limit && @processed >= @limit)
            process_one(activity)
          end
        end
      end

      def process_one(activity)
        run_id = activity[:run_id]
        polyline = activity[:summary_polyline]

        if polyline.nil? || polyline.empty? || polyline == KEEP_PLACEHOLDER
          @skipped += 1
          return
        end

        points = decode_points(polyline)
        unless points && points.size >= 2
          @skipped += 1
          return
        end

        samples = sample_points(points)
        if samples.empty?
          @skipped += 1
          return
        end

        @attempted += 1
        prefix = "[#{@attempted}/#{@total}]"

        divisions = resolve_divisions(samples)
        if divisions.empty?
          $stdout.puts "  #{prefix} #{run_id} → skipped (no divisions resolved)"
          @skipped += 1
          return
        end

        summary = build_summary(divisions, samples.size)
        update_db(run_id, summary) unless @dry_run
        $stdout.puts "  #{prefix} #{run_id} → #{format_divisions(divisions)} (#{samples.size} samples)"
        @processed += 1
      rescue => e
        $stdout.puts "  #{prefix} #{run_id} → error: #{e.message}"
        @errors += 1
      end

      def format_divisions(divisions)
        divisions.map { |d| [d[:province], d[:city], d[:district], d[:township]].compact.reject(&:empty?).join(" ") }.join(" / ")
      end

      def decode_points(polyline)
        Workouts::Geo::Polyline.decode(polyline)
      end

      def sample_points(points)
        samples = []
        last_lat = nil
        last_lng = nil
        points.each do |lat, lng|
          if last_lat.nil? ||
             (lat - last_lat).abs >= SAMPLE_INTERVAL_DEG ||
             (lng - last_lng).abs >= SAMPLE_INTERVAL_DEG
            samples << [lat.round(4), lng.round(4)]
            last_lat = lat
            last_lng = lng
          end
        end
        samples
      end

      def resolve_divisions(samples)
        key_counts = Hash.new(0)
        samples.each do |lat, lng|
          coord_key = "#{lat},#{lng}"
          raw = lookup_point_cache(coord_key)
          unless raw
            raw = @geocoder.lookup(lat, lng)
            save_point_cache(coord_key, raw) if raw[:province]
          end
          result = normalize_entry(raw)
          next unless result
          key = division_key(result)
          key_counts[key] += 1
        end
        key_counts.map do |key, count|
          province, city, district, township = key.split("|")
          { province: province, city: city, district: district, township: township, count: count }
        end.sort_by { |r| -r[:count] }
      end

      def normalize_entry(raw)
        return nil unless raw
        province = raw[:province] || raw["p"] || raw["province"]
        province = nil if province.is_a?(Array) || province.to_s.empty? || province == "中华人民共和国"
        return nil unless province
        {
          province: province,
          city: pick_field(raw, :city, "city", "c", "city") { |v| valid_name?(v) },
          district: pick_field(raw, :district, "dist", "d"),
          township: pick_field(raw, :township, "town", "t"),
        }
      end

      def pick_field(raw, *keys)
        keys.each do |k|
          v = raw[k] || raw[k.to_s]
          return v if block_given? ? yield(v) : v.is_a?(String) && !v.empty?
        end
        nil
      end

      def valid_name?(v)
        v.is_a?(String) && !v.empty? && !v.match?(/^-?\d+\.\d+,-?\d+\.\d+$/)
      end

      def division_key(result)
        [result[:province], result[:city], result[:district], result[:township]].join("|")
      end

      def build_summary(divisions, total_points)
        total = total_points.to_f
        division_list = divisions.map do |r|
          h = { p: r[:province] }
          h[:c] = r[:city] if r[:city]
          h[:d] = r[:district] if r[:district]
          h[:t] = r[:township] if r[:township]
          h[:w] = (r[:count] / total).round(4)
          h[:n] = r[:count]
          h
        end
        { divisions: division_list, total_sampled: total_points, source: "amap", processed_at: Time.now.utc.iso8601 }
      end

      def lookup_point_cache(coord_key)
        return nil unless File.exist?(POINT_CACHE_FILE)
        File.open(POINT_CACHE_FILE, "r") do |f|
          f.each_line do |line|
            entry = JSON.parse(line) rescue next
            return entry if entry["ck"] == coord_key
          end
        end
        nil
      end

      def save_point_cache(coord_key, result)
        entry = { ck: coord_key, p: result[:province], source: result[:source] }
        entry[:city] = result[:city] if result[:city]
        entry[:dist] = result[:district] if result[:district]
        entry[:town] = result[:township] if result[:township]
        File.open(POINT_CACHE_FILE, "a") { |f| f.puts(JSON.generate(entry)) }
      end

      def update_db(run_id, summary)
        @db[:activities].where(run_id: run_id).update(divisions: JSON.generate(summary[:divisions]))
      end

      def load_caches
        # Preload: nothing needed, read on-demand
      end

      def budget_exhausted?
        return false unless @time_budget
        Time.now - @start_time > @time_budget
      end

      def print_summary
        $stdout.puts "Geo detection complete: #{@processed} processed, #{@skipped} skipped, #{@errors} errors"
      end
    end
  end
end

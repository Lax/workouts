require "json"
require "fileutils"
require_relative "reverse_geocode"

module Workouts
  module Geo
    class RegionDetector
      KEEP_PLACEHOLDER = "AAAA".freeze
      SAMPLE_INTERVAL_DEG = 0.01
      CACHE_DIR = "data/cache"
      ACTIVITY_CACHE_FILE = File.join(CACHE_DIR, "geo-activities.json")
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
        FileUtils.mkdir_p(CACHE_DIR)
        load_caches
      end

      def run
        activities = pending_activities
        $stdout.puts "Activities to process: #{activities.size}"
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
          .where(Sequel.lit("region_info IS NULL"))
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
        return unless points && points.size >= 2

        samples = sample_points(points)
        return if samples.empty?

        regions = resolve_regions(samples)
        return if regions.empty?

        summary = build_summary(regions, samples.size)
        cache_activity(run_id, summary)
        update_db(run_id, summary) unless @dry_run
        @processed += 1
      rescue => e
        $stderr.puts "Error processing #{run_id}: #{e.message}"
        @errors += 1
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

      def resolve_regions(samples)
        key_counts = Hash.new(0)

        samples.each do |lat, lng|
          coord_key = "#{lat},#{lng}"
          result = lookup_point_cache(coord_key)

          unless result
            result = @geocoder.lookup(lat, lng)
            save_point_cache(coord_key, result) if result[:province]
          end

          if result[:province]
            region_key = region_key(result)
            key_counts[region_key] += 1
          end
        end

        key_counts.map do |key, count|
          province, city, district, township = key.split("|")
          { province: province, city: city, district: district, township: township, count: count }
        end.sort_by { |r| -r[:count] }
      end

      def region_key(result)
        [result[:province], result[:city], result[:district], result[:township]].join("|")
      end

      def build_summary(regions, total_points)
        total = total_points.to_f
        region_list = regions.map do |r|
          h = { p: r[:province] }
          h[:c] = r[:city] if r[:city]
          h[:d] = r[:district] if r[:district]
          h[:t] = r[:township] if r[:township]
          h[:w] = (r[:count] / total).round(4)
          h
        end
        { regions: region_list, total_sampled: total_points, source: "amap", processed_at: Time.now.utc.iso8601 }
      end

      def lookup_point_cache(coord_key)
        return nil unless File.exist?(POINT_CACHE_FILE)
        File.open(POINT_CACHE_FILE, "r") do |f|
          f.each_line do |line|
            entry = JSON.parse(line) rescue next
            return entry if entry["c"] == coord_key
          end
        end
        nil
      end

      def save_point_cache(coord_key, result)
        entry = { c: coord_key, p: result[:province], source: result[:source] }
        entry[:city] = result[:city] if result[:city]
        entry[:dist] = result[:district] if result[:district]
        entry[:town] = result[:township] if result[:township]
        File.open(POINT_CACHE_FILE, "a") { |f| f.puts(JSON.generate(entry)) }
      end

      def cache_activity(run_id, summary)
        cache = {}
        cache = JSON.parse(File.read(ACTIVITY_CACHE_FILE)) if File.exist?(ACTIVITY_CACHE_FILE)
        cache[run_id] = summary
        File.write(ACTIVITY_CACHE_FILE, JSON.pretty_generate(cache))
      end

      def update_db(run_id, summary)
        @db[:activities].where(run_id: run_id).update(region_info: JSON.generate(summary[:regions]))
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

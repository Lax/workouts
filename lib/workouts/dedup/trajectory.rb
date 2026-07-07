module Workouts
  module Dedup
    class Trajectory
      SAMPLE_RATE = 10  # take every Nth point
      PROXIMITY_M = 50  # points within 50m count as same

      def initialize(db)
        @db = db
        @cache = {}
      end

      def duplicate?(run_id_a, run_id_b)
        pts_a = cached_points(run_id_a)
        pts_b = cached_points(run_id_b)
        return nil unless pts_a && pts_b && pts_a.size >= 2 && pts_b.size >= 2

        shorter = pts_a.size <= pts_b.size ? pts_a : pts_b
        longer = pts_a.size > pts_b.size ? pts_a : pts_b

        sampled = shorter.each_slice(SAMPLE_RATE).map(&:first)
        matches = sampled.count { |pt| near(pt, longer) }
        ratio = matches.to_f / sampled.size
        ratio >= 0.3
      end

      private

      def cached_points(run_id)
        @cache[run_id] ||= load_points(run_id)
      end

      def load_points(run_id)
        source = source_from_run_id(run_id)
        return nil unless source

        std_dir = File.join("data", "std", source)
        id = run_id.sub("#{source}_", "")
        path = Dir.glob(File.join(std_dir, "#{id}.*")).first
        return nil unless path && File.exist?(path)

        data = JSON.parse(File.read(path))
        return data if data.is_a?(Array) && data.first.is_a?(Hash)

        nil
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def source_from_run_id(run_id)
        %w[garmin_cn garmin strava keep igpsport xoss xingzhe].each do |s|
          return s if run_id.start_with?("#{s}_")
        end
        nil
      end

      def near(pt, candidates)
        lat = pt["latitude"] || pt["positionLat"] || pt[:latitude] || pt[:positionLat]
        lng = pt["longitude"] || pt["positionLong"] || pt[:longitude] || pt[:positionLong]
        return false unless lat && lng

        candidates.any? do |c|
          clat = c["latitude"] || c["positionLat"] || c[:latitude] || c[:positionLat]
          clng = c["longitude"] || c["positionLong"] || c[:longitude] || c[:positionLong]
          next false unless clat && clng

          haversine(lat, lng, clat, clng) <= PROXIMITY_M
        end
      end

      def haversine(lat1, lon1, lat2, lon2)
        r = 6_371_000
        dlat = (lat2 - lat1) * Math::PI / 180
        dlon = (lon2 - lon1) * Math::PI / 180
        a = Math.sin(dlat / 2) ** 2 +
            Math.cos(lat1 * Math::PI / 180) *
            Math.cos(lat2 * Math::PI / 180) *
            Math.sin(dlon / 2) ** 2
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        r * c
      end
    end
  end
end

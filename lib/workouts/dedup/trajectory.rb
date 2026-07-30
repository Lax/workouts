module Workouts
  module Dedup
    class Trajectory
      SAMPLE_RATE = 10  # take every Nth point
      PROXIMITY_M = 50  # points within 50m count as same
      DP_EPSILON = 0.0001           # ~10m in lat/lng degrees
      CONTAINED_THRESHOLD = 0.7     # 70% overlap → equivalent/contained
      PARTIAL_THRESHOLD = 0.3       # 30% → partial boundary
      MAX_EXPECTED_COST = 1000.0    # DTW normalization denominator

      def initialize(db)
        @db = db
        @cache = {}
      end

      def duplicate?(run_id_a, run_id_b)
        pts_a = cached_points(run_id_a)
        pts_b = cached_points(run_id_b)
        return nil unless pts_a && pts_b && pts_a.size >= 2 && pts_b.size >= 2

        shorter = (pts_a.size <= pts_b.size) ? pts_a : pts_b
        longer = (pts_a.size > pts_b.size) ? pts_a : pts_b

        sampled = shorter.each_slice(SAMPLE_RATE).map(&:first)
        matches = sampled.count { |pt| near(pt, longer) }
        ratio = matches.to_f / sampled.size
        ratio >= 0.3
      end

      def points(run_id)
        cached_points(run_id)
      end

      def douglas_peucker(points, epsilon = DP_EPSILON)
        return points if points.size <= 2

        coords = points.map { |p| point_coordinates(p) }.compact
        return points if coords.size <= 2

        stack = [[0, coords.size - 1]]
        keep = Set.new([0, coords.size - 1])

        while stack.any?
          start_idx, end_idx = stack.pop
          dmax = 0.0
          idx = start_idx

          ((start_idx + 1)...end_idx).each do |i|
            d = perpendicular_distance(coords[i], coords[start_idx], coords[end_idx])
            if d > dmax
              dmax = d
              idx = i
            end
          end

          if dmax > epsilon
            keep.add(idx)
            stack.push([start_idx, idx])
            stack.push([idx, end_idx])
          end
        end

        coords.select.with_index { |_, i| keep.include?(i) }
      end

      def dtw_similarity(traj_a, traj_b)
        return nil if traj_a.nil? || traj_b.nil? || traj_a.size < 2 || traj_b.size < 2

        a = traj_a.map { |p| point_coordinates(p) }.compact
        b = traj_b.map { |p| point_coordinates(p) }.compact
        return nil if a.size < 2 || b.size < 2

        n = a.size
        m = b.size
        dtw = Array.new(n + 1) { Array.new(m + 1, Float::INFINITY) }
        dtw[0][0] = 0

        (1..n).each do |i|
          (1..m).each do |j|
            cost = haversine(a[i - 1][0], a[i - 1][1], b[j - 1][0], b[j - 1][1])
            dtw[i][j] = cost + [dtw[i - 1][j], dtw[i][j - 1], dtw[i - 1][j - 1]].min
          end
        end

        avg_cost = dtw[n][m] / [n, m].max
        [1.0 - avg_cost / MAX_EXPECTED_COST, 0.0].max
      end

      def hausdorff_distance(traj_a, traj_b)
        return nil if traj_a.nil? || traj_b.nil? || traj_a.size < 2 || traj_b.size < 2

        a_coords = traj_a.map { |p| point_coordinates(p) }.compact
        b_coords = traj_b.map { |p| point_coordinates(p) }.compact
        return nil if a_coords.size < 2 || b_coords.size < 2

        max_min_a = a_coords.map { |p| min_distance_to_set(p, b_coords) }.max || 0.0
        max_min_b = b_coords.map { |p| min_distance_to_set(p, a_coords) }.max || 0.0
        [max_min_a, max_min_b].max
      end

      def normalized_hausdorff_score(traj_a, traj_b)
        dist = hausdorff_distance(traj_a, traj_b)
        return nil if dist.nil?
        [1.0 - dist / 2000.0, 0.0].max
      end

      def overlap_score(traj_a, traj_b, radius = PROXIMITY_M)
        return nil if traj_a.nil? || traj_b.nil? || traj_a.size < 2 || traj_b.size < 2

        sampled_a = traj_a.each_slice(SAMPLE_RATE).map(&:first)
        sampled_b = traj_b.each_slice(SAMPLE_RATE).map(&:first)
        return nil if sampled_a.empty? || sampled_b.empty?

        a_in_b = sampled_a.count { |p| near(p, sampled_b) }
        b_in_a = sampled_b.count { |p| near(p, sampled_a) }

        ratio_a = a_in_b.to_f / sampled_a.size
        ratio_b = b_in_a.to_f / sampled_b.size
        (ratio_a + ratio_b) / 2.0
      end

      def containment_relation(traj_a, traj_b, radius = PROXIMITY_M, threshold = CONTAINED_THRESHOLD)
        return nil if traj_a.nil? || traj_b.nil? || traj_a.size < 2 || traj_b.size < 2

        sampled_a = traj_a.each_slice(SAMPLE_RATE).map(&:first)
        sampled_b = traj_b.each_slice(SAMPLE_RATE).map(&:first)
        return nil if sampled_a.empty? || sampled_b.empty?

        a_in_b = sampled_a.count { |p| near(p, sampled_b) } / sampled_a.size.to_f
        b_in_a = sampled_b.count { |p| near(p, sampled_a) } / sampled_b.size.to_f

        if a_in_b >= threshold && b_in_a >= threshold
          :equivalent
        elsif a_in_b >= threshold
          :contained_a
        elsif b_in_a >= threshold
          :contained_b
        elsif a_in_b > PARTIAL_THRESHOLD || b_in_a > PARTIAL_THRESHOLD
          :partial
        elsif a_in_b > 0 || b_in_a > 0
          :cross
        else
          :disjoint
        end
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
        a = Math.sin(dlat / 2)**2 +
          Math.cos(lat1 * Math::PI / 180) *
            Math.cos(lat2 * Math::PI / 180) *
            Math.sin(dlon / 2)**2
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        r * c
      end

      def point_coordinates(pt)
        lat = pt["latitude"] || pt["positionLat"] || pt[:latitude] || pt[:positionLat]
        lng = pt["longitude"] || pt["positionLong"] || pt[:longitude] || pt[:positionLong]
        [lat, lng] if lat && lng
      end

      def perpendicular_distance(pt, a, b)
        lat1, lon1 = a[0] * Math::PI / 180, a[1] * Math::PI / 180
        lat2, lon2 = b[0] * Math::PI / 180, b[1] * Math::PI / 180
        lat3, lon3 = pt[0] * Math::PI / 180, pt[1] * Math::PI / 180

        d13 = Math.acos(Math.sin(lat1) * Math.sin(lat3) + Math.cos(lat1) * Math.cos(lat3) * Math.cos(lon3 - lon1))
        theta12 = Math.atan2(Math.sin(lon2 - lon1) * Math.cos(lat2), Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(lon2 - lon1))
        theta13 = Math.atan2(Math.sin(lon3 - lon1) * Math.cos(lat3), Math.cos(lat1) * Math.sin(lat3) - Math.sin(lat1) * Math.cos(lat3) * Math.cos(lon3 - lon1))
        cross = Math.asin(Math.sin(d13) * Math.sin(theta13 - theta12))
        (cross.abs * 6371000.0)
      end

      def min_distance_to_set(pt, candidates)
        candidates.map { |c| haversine(pt[0], pt[1], c[0], c[1]) }.min
      end
    end
  end
end

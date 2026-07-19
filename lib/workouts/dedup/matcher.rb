require "time"

module Workouts
  module Dedup
    class Matcher
      WEIGHTS = { time: 0.35, distance: 0.35, duration: 0.15, category: 0.15 }.freeze
      TRAJECTORY_WEIGHTS = {
        dtw_similarity: 0.30,
        overlap_score:  0.25,
        hausdorff_score: 0.25,
        distance_match: 0.20
      }.freeze

      def self.effective_duration(act)
        [act[:moving_time].to_f, act[:elapsed_time].to_f].max
      end

      def self.external_id_match(a, b)
        a_eid = a[:external_id]
        b_eid = b[:external_id]
        return nil if a_eid.nil? || b_eid.nil?
        return nil if a_eid.empty? || b_eid.empty?

        a_normalized = a_eid.sub(%r{^strava://activities/}, "")
        b_normalized = b_eid.sub(%r{^strava://activities/}, "")

        if a_normalized == b_normalized
          { confidence: 1.0, flag: "derived", source: "external_id" }
        end
      end

      def self.match(a, b)
        exact = external_id_match(a, b)
        return exact[:confidence] if exact

        t_diff = time_diff_abs(a[:start_date], b[:start_date])
        max_diff = [300, (a[:elapsed_time] || 0).to_i, (b[:elapsed_time] || 0).to_i].max
        return 0.0 if t_diff > max_diff

        t_score = 1.0 - t_diff / max_diff.to_f
        d_score = distance_score(a[:distance].to_f, b[:distance].to_f)
        return 0.0 unless d_score

        dur_score = duration_score(effective_duration(a), effective_duration(b))
        cat_score = a[:sport_category] == b[:sport_category] ? 1.0 : -0.67

        result = t_score * WEIGHTS[:time] +
                 d_score * WEIGHTS[:distance] +
                 dur_score * WEIGHTS[:duration] +
                 cat_score * WEIGHTS[:category]
        result.round(4)
      end

      def self.time_diff_abs(t1, t2)
        t1 = t1.to_s
        t2 = t2.to_s
        return 9999 if t1.empty? || t2.empty?
        (Time.parse(t1) - Time.parse(t2)).abs
      rescue
        9999
      end

      def self.distance_score(d1, d2)
        max = [d1, d2].max
        return nil if max <= 0
        diff = (d1 - d2).abs
        return nil if diff > max * 0.15
        1.0 - diff / (max * 0.15)
      end

      def self.duration_score(d1, d2)
        max = [d1, d2].max
        return 0.0 if max <= 0
        diff = (d1 - d2).abs
        return 0.0 if diff > max * 0.15
        1.0 - diff / (max * 0.15)
      end

      def self.trajectory_score(scores)
        return 0.0 if scores.nil? || scores.empty?
        weighted = TRAJECTORY_WEIGHTS.sum do |metric, weight|
          score = scores[metric]
          next 0.0 unless score.is_a?(Numeric) && score >= 0.0 && score <= 1.0
          score * weight
        end
        weighted.round(4)
      end
    end
  end
end

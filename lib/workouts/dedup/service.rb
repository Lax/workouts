require "time"
require_relative "matcher"
require_relative "trajectory"

module Workouts
  module Dedup
    class Service
      def initialize(db)
        @db = db
        @trajectory = Trajectory.new(db)
      end

      def run
        activities = @db[:activities]
          .where(Sequel.lit("distance > 100"))
          .order(:start_date)
          .all
        return 0 if activities.size < 2

        @updates = {}
        matched = 0

        activities.each_with_index do |a, i|
          a_time = parse_time(a[:start_date])
          next unless a_time

          (i + 1...activities.size).each do |j|
            b = activities[j]
            b_time = parse_time(b[:start_date])
            break unless b_time
            break if (b_time - a_time) > 300

            score = Matcher.match(a, b)
            next unless score >= 0.15

            flag = classify_flag(a, b, score)
            append_info(a[:run_id], b[:source], b[:run_id], score, flag)
            append_info(b[:run_id], a[:source], a[:run_id], score, flag)
            matched += 1
          end
        end

        flush_updates
        matched
      end

      private

      def parse_time(val)
        return nil unless val
        Time.parse(val.to_s)
      rescue
        nil
      end

      def classify_flag(a, b, score)
        if score >= 0.85
          "derived"
        elsif @trajectory.duplicate?(a[:run_id], b[:run_id])
          "duplicate"
        elsif score >= 0.15
          "similar"
        else
          nil
        end
      end

      def append_info(run_id, source, matched_run_id, score, flag)
        return unless flag

        entry = { "source" => source, "run_id" => matched_run_id,
                  "confidence" => score, "flag" => flag }
        @updates[run_id] ||= []
        existing = @updates[run_id].find { |e| e["run_id"] == matched_run_id }
        if existing
          existing.merge!(entry)
        else
          @updates[run_id] << entry
        end
      end

      def flush_updates
        @updates.each do |run_id, entries|
          existing_json = @db[:activities].where(run_id: run_id).get(:duplicate_info)
          existing = existing_json ? JSON.parse(existing_json) : []
          merged = merge_entries(existing, entries)
          new_json = merged.empty? ? nil : JSON.generate(merged)
          @db[:activities].where(run_id: run_id).update(duplicate_info: new_json)
        end
      end

      def merge_entries(existing, new_entries)
        by_run_id = {}
        existing.each { |e| by_run_id[e["run_id"]] = e }
        new_entries.each { |e| by_run_id[e["run_id"]] = e }
        by_run_id.values
      end
    end
  end
end

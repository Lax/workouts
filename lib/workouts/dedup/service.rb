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

        by_date = activities.group_by { |a|
          t = parse_time(a[:start_date])
          t ? t.to_date : nil
        }
        by_date.delete(nil)

        by_date.each_value do |group|
          next if group.size < 2

          group.each_with_index do |a, i|
            a_range = activity_range(a)
            next unless a_range

            (i + 1...group.size).each do |j|
              b = group[j]
              b_start = parse_time(b[:start_date])
              break unless b_start
              break if b_start > a_range[:end]

              score = Matcher.match(a, b)
              next unless score >= 0.15

              flag = classify_flag(a, b, score)
              append_info(a[:run_id], b[:source], b[:run_id], score, flag)
              append_info(b[:run_id], a[:source], a[:run_id], score, flag)
              matched += 1
            end
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

      def activity_range(activity)
        t = parse_time(activity[:start_date])
        return nil unless t
        elapsed = activity[:elapsed_time] || activity[:moving_time] || 0
        { start: t, end: t + elapsed.to_i }
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
          existing = begin
            existing_json ? JSON.parse(existing_json) : []
          rescue JSON::ParserError
            []
          end
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

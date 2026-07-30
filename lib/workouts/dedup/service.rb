# frozen_string_literal: true

require "time"
require "json"
require_relative "matcher"
require_relative "trajectory"
require_relative "group_consolidator"
require_relative "log_writer"

module Workouts
  module Dedup
    class Service
      def initialize(db, incremental: false, log_path: nil, verbose: false)
        @db = db
        @trajectory = Trajectory.new(db)
        @incremental = incremental
        @log_path = log_path
        @verbose = verbose
        @updates = {}
        @matched_pairs = []
      end

      def run
        activities = activities_scope.all
        return 0 if activities.size < 2
        puts "DedupService: scanning #{activities.size} activities" if @verbose

        start_time = Time.now.utc
        matched = 0

        activities.each_with_index do |a, i|
          a_start = parse_time(a[:start_date])
          next unless a_start
          a_range = activity_range(a)

          (i + 1...activities.size).each do |j|
            b = activities[j]
            b_start = parse_time(b[:start_date])
            next unless b_start
            break if b_start > (a_range[:end] + 86400)

            score = Matcher.match(a, b)
            next unless score && score >= 0.15

            flag = classify_flag(a, b, score)
            next unless flag

            append_info(a[:run_id], b[:source], b[:run_id], score, flag)
            append_info(b[:run_id], a[:source], a[:run_id], score, flag)
            @matched_pairs << {a: a, b: b, score: score, flag: flag}
            matched += 1
          end
        end

        flush_updates

        consolidate_groups if matched > 0

        elapsed = Time.now.utc - start_time

        if @log_path
          log_stats = {
            scanned: activities.size,
            compared: @matched_pairs.size,
            matched: matched,
            by_flag: @matched_pairs.group_by { |mp| mp[:flag] }.transform_values(&:size)
          }
          LogWriter.new(@log_path).write(
            stats: log_stats,
            matches: @matched_pairs.map.with_index do |mp, idx|
              {
                id: idx + 1,
                a: {run_id: mp[:a][:run_id], source: mp[:a][:source]},
                b: {run_id: mp[:b][:run_id], source: mp[:b][:source]},
                confidence: mp[:score],
                flag: mp[:flag]
              }
            end,
            elapsed: elapsed
          )
        end

        puts "DedupService: #{matched} matches in #{elapsed.round(1)}s" if @verbose
        matched
      end

      private

      def activities_scope
        base = @db[:activities].where(Sequel.lit("distance > 100")).order(:start_date)
        return base unless @incremental
        base.where(Sequel.lit("run_id NOT IN (SELECT run_id FROM dedup_group_members)"))
      end

      def parse_time(val)
        return nil unless val
        t = Time.parse(val.to_s)
        t.utc? ? t : t.utc
      rescue
        nil
      end

      def activity_range(activity)
        duration = [activity[:elapsed_time].to_i, activity[:moving_time].to_i].max
        duration = 3600 if duration <= 0
        start_t = parse_time(activity[:start_date])
        {start: start_t, end: start_t + duration}
      end

      def classify_flag(a, b, score)
        if score >= 0.85
          "derived"
        elsif score >= 0.15
          traj_a = @trajectory.points(a[:run_id])
          traj_b = @trajectory.points(b[:run_id])

          if traj_a.nil? || traj_b.nil? || traj_a.size < 2 || traj_b.size < 2
            "similar"
          else
            containment = @trajectory.containment_relation(traj_a, traj_b)
            case containment
            when :equivalent then "duplicate"
            when :contained_a, :contained_b then "contained"
            when :partial then "partial"
            when :cross then "cross"
            else "similar"
            end
          end
        end
      end

      def append_info(run_id, source, matched_run_id, score, flag)
        return unless flag

        entry = {"source" => source, "run_id" => matched_run_id,
                 "confidence" => score, "flag" => flag}
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

      def consolidate_groups
        return if @matched_pairs.empty?

        consolidator = GroupConsolidator.new
        groups = consolidator.consolidate(@matched_pairs)

        groups.each do |group_id, run_ids|
          members = @db[:activities].where(run_id: run_ids).all
          write_dedup_group(group_id, members)
        end
      end

      def write_dedup_group(group_id, members)
        now = Time.now.utc
        @db[:dedup_groups].insert_conflict(target: :group_id).insert(
          group_id: group_id, created_at: now, updated_at: now
        )

        best = Hash.new { |h, k| h[k] = {confidence: 0.0, flag: nil} }
        @matched_pairs.each do |mp|
          [mp[:a], mp[:b]].each do |act|
            if mp[:score] > best[act[:run_id]][:confidence]
              best[act[:run_id]] = {confidence: mp[:score], flag: mp[:flag]}
            end
          end
        end

        members.each do |m|
          entry = best[m[:run_id]]
          @db[:dedup_group_members].insert_conflict(target: [:group_id, :run_id]).insert(
            group_id: group_id,
            run_id: m[:run_id],
            source: m[:source],
            flag: entry[:flag],
            confidence: entry[:confidence]
          )
        end
      end
    end
  end
end

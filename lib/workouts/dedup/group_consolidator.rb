# frozen_string_literal: true

require "digest"

module Workouts
  module Dedup
    class GroupConsolidator
      def consolidate(matched_pairs)
        parent = {}
        all_ids = []

        matched_pairs.each do |pair|
          a_id = pair[:a][:run_id]
          b_id = pair[:b][:run_id]
          all_ids << a_id << b_id
        end

        all_ids.uniq!
        return {} if all_ids.empty?

        all_ids.each { |id| parent[id] = id }

        matched_pairs.each do |pair|
          union(parent, pair[:a][:run_id], pair[:b][:run_id])
        end

        groups = Hash.new { |h, k| h[k] = [] }
        all_ids.each do |run_id|
          root = find(parent, run_id)
          groups[root] << run_id
        end

        groups.transform_values! { |ids| ids.uniq.sort }

        result = {}
        groups.each_value do |sorted_ids|
          group_id = Digest::SHA256.hexdigest(sorted_ids.join(","))[0, 16]
          result[group_id] = sorted_ids
        end
        result
      end

      private

      def find(parent, x)
        parent[x] = find(parent, parent[x]) if parent[x] != x
        parent[x]
      end

      def union(parent, x, y)
        rx = find(parent, x)
        ry = find(parent, y)
        return if rx == ry
        parent[ry] = rx
      end
    end
  end
end

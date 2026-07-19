# frozen_string_literal: true

require "json"
require "fileutils"

module Workouts
  module Dedup
    class LogWriter
      def initialize(log_path = nil)
        @log_path = log_path || default_path
        FileUtils.mkdir_p(File.dirname(@log_path))
      end

      def write(stats:, matches:, elapsed:)
        log = {
          started_at: (Time.now.utc - elapsed).iso8601,
          elapsed_seconds: elapsed.round(1),
          stats: stats,
          matches: matches
        }
        File.write(@log_path, JSON.pretty_generate(log))
        @log_path
      end

      private

      def default_path
        timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        "data/dedup/#{timestamp}.json"
      end
    end
  end
end

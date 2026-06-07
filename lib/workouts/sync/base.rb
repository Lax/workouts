require_relative "tally"

module Workouts
  module Sync
    class Base
      def initialize(config:, db:, activity_filter: nil, privacy: nil, time_budget: nil)
        @config = config
        @db = db
        @activity_filter = activity_filter
        @privacy = privacy
        @time_budget = time_budget
        @start_time = nil
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      protected

      def time_expired?
        return false unless @time_budget.is_a?(Numeric) && @time_budget > 0 && @start_time
        (Time.now - @start_time) > @time_budget
      end

      def raw_dir
        src = self.class.name.split("::").last.downcase
        src = "garmin" if src.start_with?("garmin")
        File.join("data", "raw", src)
      end

      def raw_path(platform_id)
        raise NotImplementedError
      end

      def raw_file_exists?(platform_id)
        File.exist?(raw_path(platform_id))
      end

      def l2_dir
        src = self.class.name.split("::").last.downcase
        src = "garmin" if src.start_with?("garmin")
        File.join("data", "std", src)
      end

      def l2_path(platform_id, ext = "json")
        File.join(l2_dir, "#{platform_id}.#{ext}")
      end

      def report_progress(count, total = nil)
        return if skip_progress?(count, total)

        tally = Tally.new(count)
        line = "#{source_label}: #{tally} (#{count}"
        line += "/#{total}" if total
        line += ") "
        print "\r#{line}"
        $stdout.flush
      end

      def skip_progress?(count, total)
        return false if count <= 50

        remaining = total ? total - count : Float::INFINITY
        return false if remaining <= 50

        if count > 100 && remaining > 100
          count % 10 != 0
        elsif count > 50 && remaining > 50
          count % 5 != 0
        else
          false
        end
      end

      def source_label
        self.class.name.split("::").last
      end

      def upsert_activity(attrs)
        attrs = attrs.transform_keys(&:to_s)
        now = Time.now.utc

        if @privacy && !@privacy.before_saving?
          attrs["summary_polyline"] = @privacy.filter(attrs["summary_polyline"])
        end

        existing = @db[:activities].where(run_id: attrs["run_id"]).first
        if existing
          attrs.delete("created_at")
          attrs["updated_at"] = now
          @db[:activities].where(run_id: attrs["run_id"]).update(attrs)
        else
          attrs["created_at"] ||= now
          attrs["updated_at"] ||= now
          @db[:activities].insert(attrs)
        end
      end

      def skip_type?(sport_type)
        return false unless @activity_filter
        !@activity_filter.include?(sport_type.to_s.downcase)
      end
    end
  end
end

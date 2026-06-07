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
        @progress_reported = false
      end

      attr_reader :progress_reported

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

      def std_dir
        src = self.class.name.split("::").last.downcase
        src = "garmin" if src.start_with?("garmin")
        File.join("data", "std", src)
      end

      def std_path(platform_id, ext = "json")
        File.join(std_dir, "#{platform_id}.#{ext}")
      end

      def report_progress(count, total = nil)
        return unless show_progress?(count, total)

        @progress_reported = true
        tally = Tally.new(count)
        line = "#{source_label}: #{tally} (#{count}"
        line += "/#{total}" if total
        line += ") "
        print "\r#{line}"
        $stdout.flush
      end

      def show_progress?(count, total)
        return true if count == 1
        return true if total && (total - count) <= 50

        step = progress_step(total)
        step <= 1 || count % step == 0
      end

      def progress_step(total)
        return 1 unless total && total > 0
        [1, (1.5 * (total ** 0.4)).to_i].max
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

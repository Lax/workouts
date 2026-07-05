require "date"
require_relative "tally"

module Workouts
  module Sync
    # Adapter abstract. Each source must implement: call, raw_path.
    # Contract: upsert_activity + skip_type provided. time_budget honored.
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
        return 0 unless respond_to?(:authenticate) ? authenticate : true
        ids = pending_ids
        return 0 if ids.nil? || ids.empty?
        ids.filter_map { |p| process_one(p) }.size
      end

      # 返回 [{ id:, type:, summary: }] 待同步活动列表
      def pending_ids
        raise NotImplementedError, "#{self.class} must implement #pending_ids"
      end

      # 同步单个活动（pending 是 pending_ids 的一个元素）
      # 返回 attrs hash（成功）或 nil（skip/失败）
      def process_one(pending)
        raise NotImplementedError, "#{self.class} must implement #process_one"
      end

      protected

      def time_expired?
        return false unless @time_budget.is_a?(Numeric) && @time_budget > 0 && @start_time
        (Time.now - @start_time) > @time_budget
      end

      def raw_dir
        src = self.class.name.split("::").last.downcase
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
        File.join("data", "std", src)
      end

      def std_path(platform_id, ext = "json")
        File.join(std_dir, "#{platform_id}.#{ext}")
      end

      def report_progress(count, total = nil, info = nil)
        return unless show_progress?(count, total)

        @progress_reported = true
        tally = Tally.new(count)
        line = "#{source_label}: #{tally} (#{count}"
        line += "/#{total}" if total
        line += ")"
        line += " #{info}" if info
        line += " "
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

      def build_progress_info(attrs)
        parts = []

        if (sd = attrs["start_date"] || attrs[:start_date])
          d = Date.parse(sd.to_s) rescue nil
          if d
            date_str = d.year == Date.today.year ? d.strftime("%m-%d") : d.strftime("%Y-%m-%d")
            parts << date_str
          end
        end

        type = attrs["sport_category"] || attrs[:sport_category]
        parts << type if type

        dist = attrs["distance"] || attrs[:distance]
        if dist && dist.to_f > 0
          parts << "#{format('%.1f', dist.to_f / 1000)}km"
        end

        source = attrs["source"] || attrs[:source] || source_label
        name = attrs["name"] || attrs[:name]
        display_name = name.to_s.strip
        display_name = "#{source} Activity" if display_name.empty?
        chars = display_name.chars
        display_name = chars.first(30).join + "…" if chars.size > 30
        parts << display_name

        parts.join(" | ") unless parts.empty?
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

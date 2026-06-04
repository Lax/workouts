module Workouts
  module Sync
    class Base
      def initialize(config:, db:, activity_filter: nil, privacy: nil)
        @config = config
        @db = db
        @activity_filter = activity_filter
        @privacy = privacy
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      protected

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

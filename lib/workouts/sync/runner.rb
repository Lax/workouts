module Workouts
  module Sync
    class Runner
      POISON = Object.new.freeze
      BATCH_SIZE = 5

      def initialize(sources:, db:, config:, activity_filter: nil,
                     num_workers: 3, time_budget: nil)
        @sources = sources
        @db = db
        @config = config
        @activity_filter = activity_filter
        @num_workers = num_workers
        @time_budget = time_budget
        @sync_start = Time.now

        @pending_ids = {}
        @adapters = {}
        @source_queue = Queue.new
        @output_queue = Queue.new
        @stats_lock = Mutex.new
        @unfinished = 0
        @completed = {}
        @timed_out = false
      end

      def run
        init_pending
        return 0 if @source_queue.empty?

        output_thread = Thread.new { output_loop }
        worker_threads = @num_workers.times.map { Thread.new { worker_loop } }

        worker_threads.each(&:join)
        output_queue << POISON
        output_thread.join

        Workouts::Dedup::Service.new(@db).run if @sources.size > 1
      end

      private

      attr_reader :output_queue

      def init_pending
        @sources.each do |source|
          cfg = @config.sync_config(source)
          next if cfg.nil? || cfg.empty?

          adapter = build_adapter(source, cfg)
          next unless adapter
          next unless adapter.authenticate

          ids = adapter.pending_ids
          next if ids.nil? || ids.empty?

          @adapters[source] = adapter
          @pending_ids[source] = ids
          @source_queue << source
        end
        @unfinished = @source_queue.size
      end

      def build_adapter(source, cfg)
        klass = case source
                when "strava" then Sync::Strava
                when "garmin" then Sync::Garmin
                when "garmin_cn" then Sync::GarminCN
                when "keep" then Sync::Keep
                when "igpsport" then Sync::IGPSPORT
                when "xoss" then Sync::XOSS
                when "xingzhe" then Sync::XingZhe
                end
        return nil unless klass

        klass.new(config: cfg, db: @db, activity_filter: @activity_filter)
      end

      def worker_loop
        loop do
          source = @source_queue.pop
          break if source == POISON

          processed = 0
          timed_out_local = false

          loop do
            activity = nil
            @stats_lock.synchronize { activity = @pending_ids[source]&.shift }
            break unless activity

            if @timed_out || (@time_budget && (Time.now - @sync_start) > @time_budget.to_f)
              @stats_lock.synchronize do
                @timed_out = true
                @pending_ids[source]&.unshift(activity) if @pending_ids[source]
              end
              timed_out_local = true
              break
            end

            begin
              result = @adapters[source].process_one(activity)
              @output_queue << {
                type: :progress, source: source, id: activity[:id],
                info: result ? build_info(result) : "skipped"
              }
            rescue => e
              @output_queue << { type: :error, source: source, message: e.message }
            end

            processed += 1
            break if processed >= BATCH_SIZE
          end

          finish_activity(source, timed_out_local)
        end
      end

      def finish_activity(source, timed_out = false)
        @stats_lock.synchronize do
          if timed_out
            remaining = @pending_ids[source]&.size.to_i
            @output_queue << { type: :timeout, source: source, remaining: remaining }
            @pending_ids[source]&.clear
          end

          more = @pending_ids[source]&.any?
          if more
            @source_queue << source
          else
            return if @completed[source]
            @completed[source] = true
            @unfinished -= 1
            if @unfinished <= 0
              @num_workers.times { @source_queue << POISON }
            end
          end
        end
      end

      def output_loop
        $stdout.sync = true
        per_source = Hash.new(0)
        errors = Hash.new(0)

        loop do
          msg = @output_queue.pop
          break if msg == POISON

          case msg[:type]
          when :progress
            per_source[msg[:source]] += 1
            puts "  #{msg[:source].rjust(10)} | #{msg[:info]}"
          when :error
            errors[msg[:source]] += 1
            puts "  #{msg[:source].rjust(10)} | ERROR: #{msg[:message]}"
          when :timeout
            puts "  #{msg[:source].rjust(10)} | TIME BUDGET — #{msg[:remaining]} remaining"
          end
        end

        @sources.each do |s|
          cnt = per_source[s]
          err = errors[s]
          next if cnt.to_i <= 0 && err.to_i <= 0
          label = err.to_i > 0 ? "#{cnt} synced, #{err} errors" : "#{cnt} synced"
          prefix = cnt.to_i > 0 ? "    done" : "   error"
          puts "  #{prefix}: #{s}: #{label}"
        end
      end

      def build_info(attrs)
        parts = []
        if (sd = attrs["start_date"] || attrs[:start_date])
          d = Date.parse(sd.to_s) rescue nil
          parts << (d.year == Date.today.year ? d.strftime("%m-%d") : d.strftime("%Y-%m-%d")) if d
        end
        type = attrs["sport_category"] || attrs[:sport_category]
        parts << type if type
        dist = attrs["distance"] || attrs[:distance]
        parts << "#{format('%.1f', dist.to_f / 1000)}km" if dist&.to_f&.> 0
        name = (attrs["name"] || attrs[:name]).to_s.strip
        name = "#{name}"[0, 30]
        parts << name unless name.empty?
        parts.join(" | ")
      end
    end
  end
end

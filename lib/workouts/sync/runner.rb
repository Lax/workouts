module Workouts
  module Sync
    class Runner
      POISON = Object.new.freeze
      BATCH_SIZE = 5

      def initialize(sources:, db:, config:, activity_filter: nil,
        num_workers: 3, time_budget: nil, total_timeout: nil)
        @sources = sources
        @db = db
        @config = config
        @activity_filter = activity_filter
        @num_workers = num_workers
        @time_budget = time_budget
        @total_timeout = total_timeout || ENV["SYNC__TOTAL_TIMEOUT"]&.to_f
        @total_timeout = nil if @total_timeout&.<= 0
        @sync_start = Time.now
        @watchdog = nil

        @pending_ids = {}
        @adapters = {}
        @source_queue = Queue.new
        @output_queue = Queue.new
        @stats_lock = Mutex.new
        @unfinished = 0
        @completed = {}
        @timed_out = false
        @shutdown = false
      end

      def run
        output_thread = Thread.new { output_loop }
        start_watchdog if @total_timeout
        init_pending
        unless @source_queue.empty?
          worker_threads = @num_workers.times.map { Thread.new { worker_loop } }
          worker_threads.each(&:join)
        end
        output_queue << POISON
        output_thread.join

        Workouts::Dedup::Service.new(@db).run if @sources.size > 1
      ensure
        @watchdog&.kill
      end

      private

      attr_reader :output_queue

      def init_pending
        @sources.each do |source|
          cfg = @config.sync_config(source)
          next if cfg.nil? || cfg.empty?
          @source_queue << source
        end
        @unfinished = @source_queue.size
      end

      def init_source(source)
        cfg = @config.sync_config(source)
        return false unless cfg

        output_queue << {type: :banner, source:, text: "authenticating"}
        adapter = build_adapter(source, cfg)
        unless adapter
          output_queue << {type: :banner, source:, text: "no adapter"}
          return false
        end

        unless adapter.authenticate
          output_queue << {type: :banner, source:, text: "auth failed"}
          return false
        end

        output_queue << {type: :banner, source:, text: "fetching activity list"}
        ids = adapter.pending_ids
        if ids.nil? || ids.empty?
          output_queue << {type: :banner, source:, text: "no new activities"}
          return false
        end

        @adapters[source] = adapter
        @pending_ids[source] = ids
        output_queue << {type: :banner, source:, text: "#{ids.size} pending"}
        true
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

          begin
            process_source(source)
          rescue => e
            @output_queue << {type: :error, source:, message: "Worker crashed: #{e.message}"}
            @stats_lock.synchronize do
              @pending_ids.delete(source)
              @adapters.delete(source)
              return if @completed[source]
              @completed[source] = true
              @unfinished -= 1
              if @unfinished <= 0
                @shutdown = true
                @num_workers.times { @source_queue << POISON }
              end
            end
          end
        end
      end

      def process_source(source)
        unless init_source(source)
          finish_activity(source)
          return
        end

        total = @pending_ids[source].size
        processed = 0
        timed_out_local = false

        loop do
          activity = nil
          @stats_lock.synchronize { activity = @pending_ids[source]&.shift }
          break unless activity

          if @shutdown || budget_expired?
            @stats_lock.synchronize do
              @shutdown = true
              @timed_out = true
              @pending_ids[source]&.unshift(activity) if @pending_ids[source]
            end
            timed_out_local = true
            break
          end

          begin
            result = @adapters[source].process_one(activity)
            processed += 1
            if result
              info = @adapters[source].build_progress_info(result)
              @output_queue << {
                type: :progress, source:, id: activity[:id],
                info: info, done: processed, total: total
              }
            else
              @output_queue << {
                type: :progress, source:, id: activity[:id],
                info: nil, done: processed, total: total
              }
            end
          rescue => e
            @output_queue << {type: :error, source:, message: e.message}
          end

          break if processed >= BATCH_SIZE
        end

        finish_activity(source, timed_out_local)
      end

      def finish_activity(source, timed_out = false)
        @stats_lock.synchronize do
          if timed_out
            remaining = @pending_ids[source]&.size.to_i
            @output_queue << {type: :timeout, source:, remaining:}
            @pending_ids[source]&.clear
          end

          more = @pending_ids[source]&.any?
          if more && !@shutdown
            @source_queue << source
          else
            return if @completed[source]
            @completed[source] = true
            @unfinished -= 1
            if @unfinished <= 0
              @shutdown = true
              @num_workers.times { @source_queue << POISON }
            end
          end
        end
      end

      def budget_expired?
        @time_budget && (Time.now - @sync_start) > @time_budget.to_f
      end

      def start_watchdog
        @watchdog = Thread.new do
          sleep @total_timeout
          @stats_lock.synchronize { @shutdown = true }
          @output_queue << {type: :total_timeout, seconds: @total_timeout}
          @num_workers.times { @source_queue << POISON }
        end
      end

      def output_loop
        $stdout.sync = true
        $stdout.puts "Runner started with #{@num_workers} workers, #{@sources.size} sources"
        $stdout.flush
        per_source = Hash.new { |h, k| h[k] = {} }

        loop do
          msg = @output_queue.pop
          break if msg == POISON

          s = msg[:source]
          ps = per_source[s]

          case msg[:type]
          when :banner
            text = msg[:text]
            if /auth failed/.match?(text)
              ps[:auth_failed] = true
            elsif /no new activities/.match?(text)
              ps[:up_to_date] = true
            elsif text =~ /(\d+) pending/
              ps[:total] = $1.to_i
            end
            $stdout.puts "  #{s.rjust(10)} | #{text}"
          when :progress
            ps[:done] = msg[:done] || ps.fetch(:done, 0) + 1
            total = msg[:total] || ps[:total]
            next unless show_progress?(msg[:done], total)
            line = if msg[:info]
              " [#{msg[:done]}/#{total}] #{msg[:info]}"
            else
              " [#{msg[:done]}/#{total}] (skipped)"
            end
            $stdout.puts "  #{s.rjust(10)} |#{line}"
          when :error
            ps[:errors] = (ps[:errors] || 0) + 1
            $stdout.puts "  #{s.rjust(10)} | ERROR: #{msg[:message]}"
          when :timeout
            $stdout.puts "  #{s.rjust(10)} | TIME BUDGET — #{msg[:remaining]} remaining"
          when :total_timeout
            $stdout.puts "  *** TOTAL TIMEOUT #{msg[:seconds]}s — forcing shutdown"
          end
          $stdout.flush
        end

        @sources.each do |s|
          info = per_source[s] || {}
          err = info[:errors] || 0
          if info[:auth_failed]
            $stdout.puts "    done: #{s}: 0 synced (auth failed)"
          elsif info[:up_to_date]
            $stdout.puts "    done: #{s}: up to date"
          elsif (cnt = info[:done]) && cnt > 0
            label = (err > 0) ? "#{cnt} synced, #{err} errors" : "#{cnt} synced"
            $stdout.puts "    done: #{s}: #{label}"
          elsif info.key?(:done)
            $stdout.puts "    done: #{s}: 0 synced"
          end
        end
        $stdout.flush
      end

      def show_progress?(done, total)
        return true if done.nil? || done <= 3
        return true if total && (total - done) <= 5
        step = (total && total > 0) ? [1, (total / 15.0).ceil].max : 1
        step <= 1 || done % step == 0
      end
    end
  end
end

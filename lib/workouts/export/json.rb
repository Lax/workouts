require "json"

module Workouts
  module Export
    class JSON
      def initialize(db:, output:, activity_filter: nil, tracks_output: nil)
        @db = db
        @output = output
        @activity_filter = activity_filter
        @tracks_output = tracks_output
      end

      def call
        dataset = @db[:activities].order(Sequel.desc(:start_date))
        dataset = dataset.where(sport_category: @activity_filter) if @activity_filter

        activities = dataset.all

        # Build dedup group lookup (run_id → group_id)
        run_id_to_group = {}
        @db[:dedup_group_members].each { |gm| run_id_to_group[gm[:run_id]] = gm[:group_id] }

        # Cache group members by group_id
        group_members_cache = {}

        tracks = @tracks_output ? {} : nil

        formatted = activities.map do |a|
          gid = run_id_to_group[a[:run_id]]
          if gid
            group_members_cache[gid] ||= @db[:dedup_group_members].where(group_id: gid).all
            composite_activity(a, gid, group_members_cache[gid], tracks)
          else
            format_activity(a, tracks)
          end
        end

        File.write(@output, ::JSON.pretty_generate(formatted))

        if @tracks_output
          File.write(@tracks_output, ::JSON.generate(tracks))
        end

        formatted.size
      end

      private

      def extract_polyline(a)
        if a[:source] == "keep" && a[:summary_polyline] == Workouts::Source::Keep::PLACEHOLDER_POLYLINE
          return nil
        end
        a[:summary_polyline]
      end

      def format_activity(a, tracks = nil)
        polyline = extract_polyline(a)
        if tracks && polyline
          tracks[a[:run_id]] = polyline
        end

        base = {
          run_id: a[:run_id],
          name: a[:name],
          distance: a[:distance],
          moving_time: a[:moving_time],
          type: a[:sport_category],
          sport_type: a[:sport_type],
          start_date: a[:start_date],
          start_date_local: a[:start_date_local],
          location_country: a[:location_country],
          summary_polyline: tracks ? nil : polyline,
          average_heartrate: a[:average_heartrate] && a[:average_heartrate] != 0 ? a[:average_heartrate] : nil,
          max_heartrate: a[:max_heartrate],
          average_cadence: a[:average_cadence],
          max_cadence: a[:max_cadence],
          average_power: a[:average_power],
          max_power: a[:max_power],
          calories: a[:calories],
          average_temperature: a[:average_temperature],
          average_speed: a[:average_speed],
          elevation_gain: a[:elevation_gain],
          source: a[:source],
        }
        if a[:divisions]
          base[:divisions] = ::JSON.parse(a[:divisions])
        end
        base
      end

      def composite_activity(activity, group_id, members, tracks = nil)
        run_ids = members.map { |m| m[:run_id] }
        group_activities = @db[:activities].where(run_id: run_ids).all

        elector = Workouts::Dedup::FieldElector.new
        composite = {}

        Workouts::Dedup::FieldElector::FIELD_ELECTION_RULES.each_key do |field|
          values = group_activities.map { |a| a[field] }
          sources = group_activities.map { |a| a[:source]&.to_sym }
          composite[field] = elector.elect(field, values, sources)
        end

        # Pass-through fields (identity, not electable)
        composite[:run_id] = activity[:run_id]
        composite[:source] = activity[:source]
        composite[:sport_type] = activity[:sport_type]
        composite[:start_date_local] = activity[:start_date_local]
        composite[:location_country] = activity[:location_country]
        composite[:sport_category] = activity[:sport_category]

        if composite[:distance].to_f > 0 && composite[:moving_time].to_f > 0
          composite[:average_speed] = composite[:distance] / composite[:moving_time]
        end

        # Polyline handling for composite: elect best polyline, write to tracks if needed
        polyline = composite[:summary_polyline]
        if tracks && polyline
          tracks[activity[:run_id]] = polyline
        end
        composite[:summary_polyline] = tracks ? nil : polyline

        composite[:type] = composite[:sport_category]
        composite[:dedup_group] = group_id
        composite[:member_sources] = members.map do |m|
          { source: m[:source], run_id: m[:run_id], flag: m[:flag], confidence: m[:confidence] }
        end

        composite
      end
    end
  end
end

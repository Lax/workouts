require_relative "base"

module Workouts
  module Sync
    class Strava < Base
      BASE_URL = "https://www.strava.com/api/v3"
      MAX_DETAIL_CALLS = 5
      DUPLICATE_SOURCES = %w[keep xingzhe xoss igpsport garmin garmin_cn].freeze

      def call
        @start_time = Time.now
        return 0 unless credentials_present?

        access_token = refresh_access_token
        return 0 unless access_token

        count = sync_activities(access_token)
        recheck_duplicates
        count
      end

      private

      def credentials_present?
        @config["client_id"].to_s != "" &&
        @config["client_secret"].to_s != "" &&
        @config["refresh_token"].to_s != ""
      end

      def refresh_access_token
        resp = Faraday.post("https://www.strava.com/oauth/token") do |req|
          req.body = {
            client_id: @config["client_id"],
            client_secret: @config["client_secret"],
            refresh_token: @config["refresh_token"],
            grant_type: "refresh_token"
          }
        end
        raise "Strava token refresh failed: #{resp.status}" unless resp.success?
        JSON.parse(resp.body)["access_token"]
      end

      def sync_activities(token)
        existing = existing_run_ids
        page = 1
        count = 0
        detail_calls = 0

        loop do
          activities = fetch_activities(token, page)
          break if activities.empty?

          activities.each do |act|
            act_id = act["id"].to_s
            next if existing.include?(act_id) && raw_file_exists?(act_id)
            break if time_expired?
            break if detail_calls >= MAX_DETAIL_CALLS

            count += 1 if sync_activity(act, act_id, token)
            detail_calls += 1
            report_progress(count)
          end

          page += 1
        end

        count
      end

      def sync_activity(act, act_id, token)
          dup_info = find_best_match(act["start_date"], act["distance"], act["moving_time"],
                                   map_sport_type(act["type"], act["sport_type"]))

        detail = fetch_detail(act_id, token)
        return false unless detail

        streams = fetch_streams(act_id, token)

        write_source_archive(detail, streams, act_id)

        l2 = streams_to_l2(detail, streams)
        write_standardized_json(l2, act_id) if l2

        polyline = l2 ? Geo::Polyline.encode(l2.map { |pt| [pt[:positionLat], pt[:positionLong]] }) : act.dig("map", "summary_polyline")

        type = map_sport_type(act["type"], act["sport_type"])
        return false if skip_type?(type)

        attrs = build_attrs(act, type, polyline, dup_info)
        upsert_activity(attrs)
        true
      end

      def fetch_activities(token, page)
        resp = Faraday.get("#{BASE_URL}/athlete/activities") do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.params = { page: page, per_page: 100 }
        end
        return [] unless resp.success?
        JSON.parse(resp.body)
      end

      def fetch_detail(act_id, token)
        resp = Faraday.get("#{BASE_URL}/activities/#{act_id}") do |req|
          req.headers["Authorization"] = "Bearer #{token}"
        end
        return nil unless resp.success?
        JSON.parse(resp.body)
      end

      def fetch_streams(act_id, token)
        resp = Faraday.get("#{BASE_URL}/activities/#{act_id}/streams") do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.params = { keys: "lat_lng,altitude,time,heartrate,cadence,watts,temp,velocity_smooth,distance", key_by_type: true }
        end
        return {} unless resp.success?
        JSON.parse(resp.body)
      end

      def write_source_archive(detail, streams, act_id)
        dir = raw_dir
        FileUtils.mkdir_p(dir)
        archive = { source: "strava", detail: detail, streams: streams }
        tmp = File.join(dir, ".#{act_id}.json.tmp")
        final = File.join(dir, "#{act_id}.json")
        File.write(tmp, JSON.generate(archive))
        File.rename(tmp, final)
      end

      def streams_to_l2(detail, streams)
        polyline = detail.dig("map", "polyline")
        return nil unless polyline

        coords = Geo::Polyline.decode(polyline)
        return nil if coords.empty?

        alt_data = streams["altitude"]&.dig("data")
        time_data = streams["time"]&.dig("data")
        hr_data = streams["heartrate"]&.dig("data")
        cad_data = streams["cadence"]&.dig("data")
        watts_data = streams["watts"]&.dig("data")
        temp_data = streams["temp"]&.dig("data")
        speed_data = streams["velocity_smooth"]&.dig("data")
        dist_data = streams["distance"]&.dig("data")

        coords.each_with_index.map do |latlng, i|
          pt = { positionLat: latlng[0], positionLong: latlng[1] }
          pt[:altitude] = alt_data[i] if alt_data && i < alt_data.size
          pt[:timestamp] = time_data[i] if time_data && i < time_data.size
          pt[:heartRate] = hr_data[i] if hr_data && i < hr_data.size
          pt[:cadence] = cad_data[i] if cad_data && i < cad_data.size
          pt[:power] = watts_data[i] if watts_data && i < watts_data.size
          pt[:temperature] = temp_data[i] if temp_data && i < temp_data.size
          pt[:speed] = speed_data[i] if speed_data && i < speed_data.size
          pt[:distance] = dist_data[i] if dist_data && i < dist_data.size
          pt
        end
      end

      def write_standardized_json(l2, act_id)
        dir = std_dir
        FileUtils.mkdir_p(dir)
        tmp = File.join(dir, ".#{act_id}.json.tmp")
        final = File.join(dir, "#{act_id}.json")
        File.write(tmp, JSON.generate(l2))
        File.rename(tmp, final)
      end

      def recheck_duplicates
        rows = @db[:activities].where(source: "strava").all
        rows.each do |s|
          next unless s[:distance] && s[:distance] > 100
          best = find_best_match(s[:start_date], s[:distance], s[:moving_time], s[:sport_category])
          new_json = best && best[:confidence] > 0.15 ? JSON.generate([best]) : nil
          current = s[:duplicate_info]
          next if new_json == current || (new_json && current && JSON.parse(new_json) == JSON.parse(current))
          @db[:activities].where(run_id: s[:run_id]).update(duplicate_info: new_json)
        end
        nil
      end

      def find_best_match(start_date, distance, moving_time, category)
        return nil unless distance && distance > 100

        candidates = @db[:activities]
          .where(source: DUPLICATE_SOURCES, sport_category: category)
          .exclude(distance: nil)
          .all

        best = nil
        best_conf = 0.0

        candidates.each do |c|
          t_diff = begin
            (Time.parse(start_date) - Time.parse(c[:start_date].to_s)).abs
          rescue
            9999
          end
          next if t_diff > 300

          max_dist = [distance, c[:distance] || 0].max
          d_diff = (distance - (c[:distance] || 0)).abs
          next if max_dist == 0 || d_diff > max_dist * 0.15

          max_dur = [moving_time, c[:moving_time] || 0].max
          dur_diff = (moving_time - (c[:moving_time] || 0)).abs

          t_score = [1.0 - t_diff / 300.0, 0.0].max
          d_score = max_dist > 0 ? [1.0 - d_diff / (max_dist * 0.15), 0.0].max : 0.0
          dur_score = max_dur > 0 && dur_diff <= max_dur * 0.15 ? [1.0 - dur_diff / (max_dur * 0.15), 0.0].max : 0.0
          conf = (t_score * 0.4 + d_score * 0.4 + dur_score * 0.2).round(4)

          if conf > best_conf
            best_conf = conf
            best = { source: c[:source], run_id: c[:run_id], confidence: conf,
                     primary_distance: c[:distance] }
          end
        end

        return nil unless best && best_conf >= 0.15

        best[:flag] = best_conf >= 0.85 ? "derived" : "overlap"
        best
      end

      def build_attrs(act, category, polyline = nil, dup_info = nil)
        start_t = Time.parse(act["start_date"]) rescue nil
        local_t = Time.parse(act["start_date_local"]) rescue nil

        {
          run_id: "strava_#{act["id"]}",
          name: act["name"],
          distance: act["distance"],
          moving_time: act["moving_time"],
          elapsed_time: act["elapsed_time"],
          sport_category: category,
          sport_type: (act["sport_type"] || act["type"])&.downcase,
          start_date: start_t&.strftime("%Y-%m-%d %H:%M:%S"),
          start_date_local: local_t&.strftime("%Y-%m-%d %H:%M:%S"),
          location_country: act["location_country"],
          summary_polyline: polyline,
          average_heartrate: act["average_heartrate"],
          average_speed: act["average_speed"],
          elevation_gain: act["total_elevation_gain"],
          duplicate_info: dup_info ? JSON.generate([dup_info]) : nil,
          source: "strava"
        }
      end

      def map_sport_type(type, sport_type)
        SportMapper.canonicalize(sport_type || type)
      end

      def raw_path(platform_id)
        File.join(raw_dir, "#{platform_id}.json")
      end

      def existing_run_ids
        @db[:activities].where(source: "strava").select_map(:run_id)
          .map { |id| id.sub("strava_", "") }
      end
    end
  end
end

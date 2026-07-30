require "time"

module Workouts
  module Parser
    class TCX < Base
      NS = {tcx: "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"}.freeze

      def call(input)
        doc = input.is_a?(String) ? Nokogiri::XML(input) : input

        activities = doc.xpath("//tcx:Activities/tcx:Activity", NS)
        return [] if activities.empty?

        activities.filter_map { |act| parse_activity(act) }
      end

      private

      def parse_activity(act)
        sport = act["Sport"]
        laps = act.xpath("tcx:Lap", NS)
        return nil if laps.empty?
        lap_data = laps.map { |lap| parse_lap(lap) }.compact
        return nil if lap_data.empty?

        total_distance = lap_data.sum { |ld| ld[:distance] || 0.0 }
        total_moving_time = lap_data.sum { |ld| ld[:moving_time] || 0 }
        total_elapsed_time = lap_data.sum { |ld| ld[:elapsed_time] || 0 }
        elevation_gain = lap_data.sum { |ld| ld[:elevation_gain] || 0.0 }
        avg_hr = lap_data.map { |ld| ld[:avg_hr] }.compact
        all_points = lap_data.flat_map { |ld| ld[:points] }

        times = all_points.map { |p| p[3] }.compact
        start_date = times.min
        times.max

        data = {
          run_id: build_run_id("tcx", start_date&.strftime("%Y%m%dT%H%M%S") || SecureRandom.hex(4)),
          name: act.at_xpath("tcx:Notes", NS)&.text,
          distance: total_distance,
          moving_time: total_moving_time,
          elapsed_time: total_elapsed_time,
          sport_category: normalize_sport_type(sport),
          sport_type: sport,
          start_date: start_date,
          start_date_local: start_date,
          location_country: nil,
          summary_polyline: simplify_polyline(all_points.map { |p| [p[0], p[1]] }),
          average_heartrate: avg_hr.empty? ? nil : (avg_hr.sum / avg_hr.size).round(1),
          elevation_gain: elevation_gain,
          source: "tcx"
        }

        build_activity_attrs(data)
      end

      def parse_lap(lap)
        points = parse_track(lap)
        return nil if points.empty?

        distance = lap.at_xpath("tcx:DistanceMeters", NS)&.text&.to_f
        total_time = lap.at_xpath("tcx:TotalTimeSeconds", NS)&.text&.to_f
        lap.at_xpath("tcx:MaximumSpeed", NS)&.text&.to_f
        lap.at_xpath("tcx:Calories", NS)&.text&.to_f

        avg_hr_node = lap.at_xpath("tcx:AverageHeartRateBpm/tcx:Value", NS)
        avg_hr = avg_hr_node&.text&.to_f

        elev_gain = 0.0
        if points.length >= 2
          elev_gain = elevation_gain(points)
        end

        moving_time = moving_time_from_points(points, threshold_s: 30)

        {
          distance: distance,
          elapsed_time: total_time&.round,
          moving_time: (moving_time > 0) ? moving_time : (total_time&.round || 0),
          avg_hr: avg_hr,
          elevation_gain: elev_gain,
          points: points
        }
      end

      def parse_track(lap)
        track = lap.at_xpath("tcx:Track", NS)
        return [] unless track

        track.xpath("tcx:Trackpoint", NS).filter_map do |tp|
          pos = tp.at_xpath("tcx:Position", NS)
          next unless pos

          lat = pos.at_xpath("tcx:LatitudeDegrees", NS)&.text&.to_f
          lon = pos.at_xpath("tcx:LongitudeDegrees", NS)&.text&.to_f
          next unless lat && lon

          elev = tp.at_xpath("tcx:AltitudeMeters", NS)&.text&.to_f
          time = parse_time(tp.at_xpath("tcx:Time", NS)&.text)
          hr = tp.at_xpath("tcx:HeartRateBpm/tcx:Value", NS)&.text&.to_f

          [lat, lon, elev, time, hr]
        end
      end

      def parse_time(str)
        return nil unless str
        Time.parse(str)
      rescue ArgumentError
        nil
      end
    end
  end
end

require "time"

module Workouts
  module Parser
    class GPX < Base
      NS = { gpx: "http://www.topografix.com/GPX/1/1" }.freeze

      def call(input)
        doc = input.is_a?(String) ? Nokogiri::XML(input) : input
        doc.remove_namespaces!

        tracks = doc.xpath("//trk")
        return [] if tracks.empty?

        tracks.filter_map { |trk| parse_track(trk) }
      end

      private

      def parse_track(trk)
        name = trk.at_xpath("name")&.text
        segments = trk.xpath("trkseg")
        return nil if segments.empty?

        points = segments.flat_map { |seg| parse_segment(seg) }
        return nil if points.empty?

        times = points.map { |p| p[3] }.compact
        start_date = times.min
        end_date = times.max

        data = {
          run_id: build_run_id("gpx", start_date&.strftime("%Y%m%dT%H%M%S") || SecureRandom.hex(4)),
          name: name,
          distance: total_distance(points),
          moving_time: moving_time_from_points(points),
          elapsed_time: elapsed_time_from_points(points),
          sport_category: default_sport,
          sport_type: nil,
          start_date: start_date,
          start_date_local: start_date,
          location_country: nil,
          summary_polyline: simplify_polyline(points.map { |p| [p[0], p[1]] }),
          average_heartrate: average_heartrate(points),
          elevation_gain: elevation_gain(points),
          source: "gpx"
        }

        build_activity_attrs(data)
      end

      def parse_segment(seg)
        seg.xpath("trkpt").filter_map do |pt|
          lat = pt["lat"]&.to_f
          lon = pt["lon"]&.to_f
          next unless lat && lon

          elev = pt.at_xpath("ele")&.text&.to_f
          time = parse_time(pt.at_xpath("time")&.text)
          hr = parse_heartrate(pt)

          [lat, lon, elev, time, hr]
        end
      end

      def parse_heartrate(pt)
        ext = pt.at_xpath("extensions")
        return nil unless ext

        hr = ext.at_xpath(".//hr")
        hr&.text&.to_f
      end

      def average_heartrate(points)
        hrs = points.map { |p| p[4] }.compact
        return nil if hrs.empty?
        hrs.sum / hrs.size
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

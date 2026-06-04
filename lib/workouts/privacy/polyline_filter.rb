module Workouts
  module Privacy
    class PolylineFilter
      def initialize(config: {})
        @start_end_range = (config["start_end_range"] || 200).to_f / 1000.0
        @ignore_polyline = decode_polyline(config["polyline"]) if config["polyline"]
        @ignore_range = (config["range"] || 0).to_f / 1000.0
        @before_saving = config["before_saving"] || false
      end

      def before_saving?
        @before_saving
      end

      def filter(polyline_str)
        return nil if polyline_str.nil? || polyline_str.empty?

        points = decode_polyline(polyline_str)
        return polyline_str if points.nil? || points.empty?

        points = filter_start_end(points)
        points = filter_range(points)

        return nil if points.empty?
        encode_polyline(points)
      end

      private

      def filter_start_end(points)
        return points if @start_end_range <= 0

        start_idx = 0
        dist = 0.0
        (1...points.length).each do |i|
          dist += haversine(points[i], points[i - 1])
          start_idx = i
          break if dist > @start_end_range
        end

        end_idx = points.length - 1
        dist = 0.0
        (points.length - 2).downto(0) do |i|
          dist += haversine(points[i], points[i + 1])
          end_idx = i
          break if dist > @start_end_range
        end

        return [] if start_idx >= end_idx
        points[start_idx..end_idx]
      end

      def filter_range(points)
        return points if @ignore_polyline.nil? || @ignore_range <= 0

        points.reject do |point|
          @ignore_polyline.any? { |ip| haversine(point, ip) < @ignore_range }
        end
      end

      def haversine(p1, p2)
        lat1 = deg_to_rad(p1[0])
        lat2 = deg_to_rad(p2[0])
        dlat = deg_to_rad(p2[0] - p1[0])
        dlon = deg_to_rad(p2[1] - p1[1])

        a = Math.sin(dlat / 2) ** 2 +
            Math.cos(lat1) * Math.cos(lat2) *
            Math.sin(dlon / 2) ** 2
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        6371.0 * c
      end

      def deg_to_rad(deg)
        deg * Math::PI / 180.0
      end

      def decode_polyline(str)
        return nil unless str && str.length > 0

        points = []
        index = 0
        lat = 0
        lng = 0

        while index < str.length
          shift = 0
          result = 0
          begin
            byte = str[index].ord - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
          end while byte >= 0x20

          dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
          lat += dlat

          shift = 0
          result = 0
          begin
            byte = str[index].ord - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
          end while byte >= 0x20

          dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
          lng += dlng

          points << [lat * 1e-5, lng * 1e-5]
        end

        points
      end

      def encode_polyline(points)
        result = ""
        plat = 0
        plng = 0

        points.each do |lat, lng|
          dlat = ((lat * 1e5).round - plat)
          dlng = ((lng * 1e5).round - plng)

          plat += dlat
          plng += dlng

          result += encode_number(dlat)
          result += encode_number(dlng)
        end

        result
      end

      def encode_number(num)
        num = num < 0 ? ~(num << 1) : (num << 1)
        result = ""

        while num >= 0x20
          result += ((0x20 | (num & 0x1f)) + 63).chr
          num >>= 5
        end

        result += (num + 63).chr
        result
      end
    end
  end
end

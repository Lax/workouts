module Workouts
  module Geo
    module Polyline
      module_function

      def decode(str)
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

      def encode(points)
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

module Workouts
  module Geo
    module CoordTransform
      A = 6378245.0
      EE = 0.00669342162296594323

      X_PI = Math::PI * 3000.0 / 180.0

      module_function

      def wgs84_to_gcj02(lat, lng)
        return [lat, lng] if out_of_china(lng, lat)

        dlat, dlng = delta(lat, lng)
        [lat + dlat, lng + dlng]
      end

      def gcj02_to_wgs84(lat, lng)
        return [lat, lng] if out_of_china(lng, lat)

        dlat, dlng = delta(lat, lng)
        [lat - dlat, lng - dlng]
      end

      def gcj02_to_wgs84_exact(lat, lng)
        return [lat, lng] if out_of_china(lng, lat)

        init_lat = lat
        init_lng = lng
        5.times do
          dlat, dlng = delta(init_lat, init_lng)
          init_lat = lat - dlat
          init_lng = lng - dlng
        end
        [init_lat, init_lng]
      end

      def gcj02_to_bd09(lat, lng)
        return [lat, lng] if out_of_china(lng, lat)

        x = lng
        y = lat
        z = Math.sqrt(x * x + y * y) + 0.00002 * Math.sin(y * X_PI)
        theta = Math.atan2(y, x) + 0.000003 * Math.cos(x * X_PI)

        bd_lng = z * Math.cos(theta) + 0.0065
        bd_lat = z * Math.sin(theta) + 0.006
        [bd_lat, bd_lng]
      end

      def bd09_to_gcj02(lat, lng)
        return [lat, lng] if out_of_china(lng, lat)

        x = lng - 0.0065
        y = lat - 0.006
        z = Math.sqrt(x * x + y * y) - 0.00002 * Math.sin(y * X_PI)
        theta = Math.atan2(y, x) - 0.000003 * Math.cos(x * X_PI)

        gcj_lng = z * Math.cos(theta)
        gcj_lat = z * Math.sin(theta)
        [gcj_lat, gcj_lng]
      end

      def bd09_to_wgs84(lat, lng)
        gcj_lat, gcj_lng = bd09_to_gcj02(lat, lng)
        gcj02_to_wgs84_exact(gcj_lat, gcj_lng)
      end

      def wgs84_to_bd09(lat, lng)
        gcj_lat, gcj_lng = wgs84_to_gcj02(lat, lng)
        gcj02_to_bd09(gcj_lat, gcj_lng)
      end

      def out_of_china(lng, lat)
        lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271
      end

      def delta(lat, lng)
        dlat = transform_lat(lng - 105.0, lat - 35.0)
        dlng = transform_lng(lng - 105.0, lat - 35.0)

        radlat = lat / 180.0 * Math::PI
        magic = Math.sin(radlat)
        magic = 1 - EE * magic * magic
        sqrt_magic = Math.sqrt(magic)

        dlat = (dlat * 180.0) / ((A * (1 - EE)) / (magic * sqrt_magic) * Math::PI)
        dlng = (dlng * 180.0) / (A / sqrt_magic * Math.cos(radlat) * Math::PI)

        [dlat, dlng]
      end

      def transform_lat(x, y)
        ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(x.abs)
        ret += (20.0 * Math.sin(6.0 * x * Math::PI) + 20.0 * Math.sin(2.0 * x * Math::PI)) * 2.0 / 3.0
        ret += (20.0 * Math.sin(y * Math::PI) + 40.0 * Math.sin(y / 3.0 * Math::PI)) * 2.0 / 3.0
        ret += (160.0 * Math.sin(y / 12.0 * Math::PI) + 320.0 * Math.sin(y * Math::PI / 30.0)) * 2.0 / 3.0
        ret
      end

      def transform_lng(x, y)
        ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(x.abs)
        ret += (20.0 * Math.sin(6.0 * x * Math::PI) + 20.0 * Math.sin(2.0 * x * Math::PI)) * 2.0 / 3.0
        ret += (20.0 * Math.sin(x * Math::PI) + 40.0 * Math.sin(x / 3.0 * Math::PI)) * 2.0 / 3.0
        ret += (150.0 * Math.sin(x / 12.0 * Math::PI) + 300.0 * Math.sin(x / 30.0 * Math::PI)) * 2.0 / 3.0
        ret
      end
    end
  end
end

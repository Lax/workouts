require "fileutils"
require "json"
require "time"

module Workouts
  module Export
    class GPX
      CATEGORY_MAP = {
        "run" => "running", "ride" => "cycling", "walk" => "walking",
        "hike" => "hiking", "swim" => "swimming", "ski" => "skiing",
        "workout" => "other", "other" => "other"
      }.freeze

      def initialize(db:, output:, activity_filter: nil)
        @db = db
        @output = output
        @activity_filter = activity_filter
      end

      def call
        FileUtils.mkdir_p(@output)
        activities = load_activities
        return 0 if activities.empty?

        activities.each { |a| write_gpx(a) }
        activities.size
      end

      private

      def load_activities
        ds = @db[:activities]
          .where(Sequel.lit("summary_polyline IS NOT NULL AND summary_polyline != ?", ""))
          .order(Sequel.desc(:start_date))
        ds = ds.where(sport_category: @activity_filter) if @activity_filter
        ds.all
      end

      def write_gpx(a)
        points = l2_points(a) || polyline_points(a)
        return unless points && points.size >= 2

        safe_id = a[:run_id].to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
        name = esc(a[:name] || "Activity")
        type = CATEGORY_MAP[a[:sport_category]] || "other"
        start_t = (Time.parse(a[:start_date].to_s).utc.xmlschema(0) rescue "") if a[:start_date]

        xml = +%{<?xml version="1.0" encoding="UTF-8"?>\n}
        xml << %{<gpx version="1.1" creator="Workouts CLI"\n}
        xml << %{  xmlns="http://www.topografix.com/GPX/1/1"\n}
        xml << %{  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">\n}
        xml << %{<metadata>\n  <name>#{name}</name>\n  <time>#{start_t}</time>\n</metadata>\n}
        xml << %{<trk>\n  <name>#{name}</name>\n  <type>#{type}</type>\n  <trkseg>\n}

        points.each do |pt|
          s = +%(  <trkpt lat="#{fmt(pt[:lat])}" lon="#{fmt(pt[:lon])}">\n)
          s << %(    <ele>#{fmt(pt[:ele])}</ele>\n) if pt[:ele]
          s << %(    <time>#{pt[:time]}</time>\n) if pt[:time]
          if pt[:hr] || pt[:cad] || pt[:watts] || pt[:temp]
            s << %(    <extensions>\n)
            s << %(      <gpxtpx:TrackPointExtension>\n)
            s << %(        <gpxtpx:hr>#{pt[:hr].to_i}</gpxtpx:hr>\n) if pt[:hr]
            s << %(        <gpxtpx:cad>#{pt[:cad].to_i}</gpxtpx:cad>\n) if pt[:cad]
            s << %(        <gpxtpx:watts>#{pt[:watts].to_i}</gpxtpx:watts>\n) if pt[:watts]
            s << %(        <gpxtpx:temp>#{pt[:temp].to_i}</gpxtpx:temp>\n) if pt[:temp]
            s << %(      </gpxtpx:TrackPointExtension>\n)
            s << %(    </extensions>\n)
          end
          s << %(  </trkpt>\n)
          xml << s
        end

        xml << %{</trkseg>\n</trk>\n</gpx>\n}
        File.write(File.join(@output, "#{safe_id}.gpx"), xml)
      end

      def l2_points(a)
        id = extract_id(a[:run_id])
        src = a[:source]
        path = File.join("data", "std", src.to_s, "#{id}.json")
        return nil unless File.exist?(path)

        records = ::JSON.parse(File.read(path))
        return nil if records.empty?

        start_time = Time.parse(a[:start_date].to_s) rescue nil if a[:start_date]
        pts = []
        records.each do |r|
          lat = r["positionLat"] || r["latitude"]
          lng = r["positionLong"] || r["longitude"]
          next unless lat && lng

          ele = r["altitude"]
          ts_raw = r["timestamp"]
          time = case ts_raw
                 when String then Time.parse(ts_raw) rescue nil
                 when Numeric then start_time ? start_time + ts_raw : nil
                 end
          hr    = r["heartRate"] || r["heartrate"]
          cad   = r["cadence"]
          watts = r["power"] || r["watts"]
          temp  = r["temperature"]
          pts << { lat: lat, lon: lng, ele: ele, time: time&.utc&.xmlschema,
                   hr: hr, cad: cad, watts: watts, temp: temp }
        end
        pts.size >= 2 ? pts : nil
      end

      def polyline_points(a)
        pts = Geo::Polyline.decode(a[:summary_polyline])
        return nil if pts.size < 2
        pts.map { |lat, lng| { lat: lat, lon: lng } }
      end

      def extract_id(run_id)
        run_id.to_s.sub(/^[^_]+_/, "")
      end

      def fmt(v)
        case v
        when Float then v.round(6).to_s
        when nil then ""
        else v.to_s
        end
      end

      def esc(s)
        s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
          .gsub("'", "&apos;").gsub('"', "&quot;")
      end
    end
  end
end

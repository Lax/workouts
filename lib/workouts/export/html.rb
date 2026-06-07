require "fileutils"
require "json"
require "time"

module Workouts
  module Export
    class HTML
      CATEGORY_COLORS = {
        "run"  => "#4DD2FF",
        "walk" => "#4ECDC4",
        "ride" => "#FF6B6B",
        "hike" => "#FFD93D",
      }.freeze

      def initialize(db:, output:, activity_filter: nil)
        @db = db
        @output = output
        @activity_filter = activity_filter
      end

      def call
        FileUtils.mkdir_p(@output)
        FileUtils.mkdir_p(File.join(@output, "svg"))

        activities = load_activities
        return 0 if activities.empty?

        stats = Analysis::Calculator.new(db: @db, activity_filter: @activity_filter).call
        write_index(activities, stats)
        write_activity_pages(activities)

        activities.size
      end

      private

      def load_activities
        ds = @db[:activities].order(Sequel.desc(:start_date))
        ds = ds.where(sport_category: @activity_filter) if @activity_filter
        ds.all
      end

      def write_index(activities, stats)
        categories = activities.map { |a| a[:sport_category] }.uniq.compact.sort
        svg_path = File.join(@output, "svg", "github.svg")
        svg_content = File.exist?(svg_path) ? File.read(svg_path) : ""

        html = build_index_html(activities, stats, categories, svg_content)
        File.write(File.join(@output, "index.html"), html)
      end

      def write_activity_pages(activities)
        activities.each do |a|
          next unless a[:summary_polyline] && !a[:summary_polyline].empty?
          html = build_activity_html(a)
          safe_id = a[:run_id].gsub(/[^a-zA-Z0-9_-]/, "_")
          File.write(File.join(@output, "activity_#{safe_id}.html"), html)
        end
      end

      def build_index_html(activities, stats, categories, svg_content)
        summary = stats[:summary]
        monthly = stats[:monthly]

        yearly_dist = monthly.group_by { |m| m[:year] }.map { |y, ms|
          total_km = ms.sum { |m| m[:distance_km] }
          total_cnt = ms.sum { |m| m[:count] }
          "#{y}: #{format("%.0f", total_km)}km / #{total_cnt}次"
        }.join(" · ")

        legend_items = categories.map { |c|
          color = CATEGORY_COLORS[c] || "#888888"
          %(<label for="s-#{c}" style="background-color:#{color}">#{c.capitalize}</label>)
        }.join("\n            ")

        hide_rules = categories.map { |c|
          others = categories.reject { |o| o == c }
          "#s-#{c}:checked ~ .poster g:not(.s-#{c}) rect { fill: #444444 !important; }"
        }.join("\n          ")

        filter_inputs = categories.map { |c|
          %(<input type="radio" name="s" id="s-#{c}">)
        }.join("\n            ")

        breakdown_bars = (summary[:sport_breakdown] || []).map { |b|
          pct = summary[:total_distance_km] > 0 ? (b[:distance_km] / summary[:total_distance_km] * 100).round : 0
          color = CATEGORY_COLORS[b[:category]] || "#888888"
          bar_w = [pct, 5].max
          %(<div class="stat-bar"><span class="stat-label" style="color:#{color}">#{b[:category]}</span><div class="bar-track"><div class="bar-fill" style="width:#{bar_w}%;background:#{color}"></div></div><span class="stat-value">#{format("%.0f", b[:distance_km])}km / #{b[:count]}次</span></div>)
        }.join("\n          ")

        monthly_bars = monthly.last(12).map { |m|
          bar_pct = monthly.last(12).map { |x| x[:distance_km] }.max.to_f
          h = bar_pct > 0 ? (m[:distance_km] / bar_pct * 60).round : 0
          %(<div class="m-bar"><div class="m-bar-fill" style="height:#{h}px" title="#{m[:year]}-#{format('%02d', m[:month])}: #{format('%.0f', m[:distance_km])}km"></div><div class="m-label">#{m[:month]}月</div></div>)
        }.join("\n          ")

        activity_links = activities.first(100).map { |a|
          next nil unless a[:summary_polyline] && !a[:summary_polyline].empty?
          safe_id = a[:run_id].gsub(/[^a-zA-Z0-9_-]/, "_")
          dist = a[:distance] ? format("%.1f", a[:distance] / 1000.0) : "?"
          cat = a[:sport_category] || "?"
          %(<a href="activity_#{safe_id}.html" class="act-link" data-cat="#{cat}">#{format_date(a[:start_date])} #{dist}km #{cat}</a>)
        }.compact.join("\n            ")

        <<~HTML
          <!DOCTYPE html>
          <html lang="zh-CN">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Workouts</title>
            <style>
              * { box-sizing: border-box; }
              body { background: #222; color: #eee; font-family: -apple-system,BlinkMacSystemFont,sans-serif; margin: 0; padding: 1rem; }
              a { color: #4DD2FF; }
              h1 { text-align: center; margin: 0.5rem 0; font-size: 1.4rem; }
              .subtitle { text-align: center; color: #888; font-size: 0.85rem; margin-bottom: 1rem; }
              input[name="s"] { display: none; }
              .poster svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
              .legend { display: flex; gap: 0.5rem; justify-content: center; padding: 0.5rem; flex-wrap: wrap; }
              .legend label { cursor: pointer; padding: 0.25rem 0.75rem; border-radius: 4px; color: #fff; font-size: 0.85rem; border: 2px solid transparent; }
              .legend label:hover { border-color: #fff; }
              #s-all:checked ~ .legend label[for="s-all"] { border-color: #fff; }
              #{categories.map { |c| "#s-#{c}:checked ~ .legend label[for=\"s-#{c}\"]" }.join(", ")} { border-color: #fff; }
              #{hide_rules}
              .stats { max-width: 600px; margin: 2rem auto; padding: 1rem; background: #2a2a2a; border-radius: 8px; }
              .stat-row { display: flex; justify-content: space-around; text-align: center; margin-bottom: 1rem; }
              .stat-item { flex: 1; }
              .stat-num { font-size: 1.5rem; font-weight: bold; color: #4DD2FF; display: block; }
              .stat-desc { font-size: 0.75rem; color: #888; }
              .stat-bar { display: flex; align-items: center; gap: 0.5rem; margin: 0.3rem 0; font-size: 0.8rem; }
              .stat-label { width: 3rem; text-align: right; font-weight: bold; }
              .bar-track { flex: 1; height: 12px; background: #444; border-radius: 6px; overflow: hidden; }
              .bar-fill { height: 100%; border-radius: 6px; transition: width 0.3s; }
              .stat-value { width: 8rem; color: #aaa; }
              .yearly-summary { text-align: center; color: #888; font-size: 0.8rem; margin: 0.5rem 0; }
              .monthly-chart { display: flex; align-items: flex-end; gap: 4px; height: 80px; margin: 1rem 0; justify-content: center; }
              .m-bar { display: flex; flex-direction: column; align-items: center; width: 24px; }
              .m-bar-fill { width: 16px; background: #4DD2FF; border-radius: 3px 3px 0 0; min-height: 2px; transition: height 0.3s; }
              .m-label { font-size: 0.6rem; color: #888; margin-top: 2px; }
              .act-list { max-width: 600px; margin: 1rem auto; padding: 1rem; background: #2a2a2a; border-radius: 8px; max-height: 400px; overflow-y: auto; }
              .act-list summary { cursor: pointer; font-size: 0.85rem; color: #888; }
              .act-link { display: block; padding: 0.3rem 0.5rem; color: #ccc; text-decoration: none; font-size: 0.8rem; border-radius: 3px; }
              .act-link:hover { background: #333; color: #fff; }
              @media (max-width: 767px) {
                .stat-row { flex-wrap: wrap; gap: 0.5rem; }
                .stat-item { min-width: 45%; }
              }
            </style>
          </head>
          <body>
            <h1>Workouts</h1>
            <p class="subtitle">#{yearly_dist}</p>

            <input type="radio" name="s" id="s-all" checked>
            #{filter_inputs}
            <div class="legend">
              <label for="s-all">All</label>
              #{legend_items}
            </div>
            <div class="poster">
              #{svg_content}
            </div>

            <div class="stats">
              <div class="stat-row">
                <div class="stat-item"><span class="stat-num">#{summary[:total_activities]}</span><span class="stat-desc">总运动</span></div>
                <div class="stat-item"><span class="stat-num">#{format("%.0f", summary[:total_distance_km])}</span><span class="stat-desc">总距离 (km)</span></div>
                <div class="stat-item"><span class="stat-num">#{format("%.0f", summary[:total_moving_time_h])}</span><span class="stat-desc">总时长 (h)</span></div>
              </div>
              #{breakdown_bars}
              <div class="yearly-summary">月趋势（近12月）</div>
              <div class="monthly-chart">#{monthly_bars}</div>
            </div>

            <details class="act-list">
              <summary>活动列表（最近 100 条，有轨迹可查看）</summary>
              #{activity_links}
            </details>

            <p style="text-align:center;font-size:0.75rem;color:#555;margin-top:2rem">
              <a href="activities.json">JSON</a> · <a href="stats.json">Stats</a> · Generated by Workouts CLI
            </p>
          </body>
          </html>
        HTML
      end

      def build_activity_html(a)
        polyline = a[:summary_polyline]
        points_json = if polyline && !polyline.empty?
                        pts = Geo::Polyline.decode(polyline)
                        pts ? ::JSON.generate(pts) : "[]"
                      else
                        "[]"
                      end

        dist_km = a[:distance] ? format("%.2f", a[:distance] / 1000.0) : "?"
        pace = if a[:moving_time] && a[:moving_time] > 0 && a[:distance] && a[:distance] > 0
                 sec_per_km = a[:moving_time] / (a[:distance] / 1000.0)
                 min = (sec_per_km / 60).to_i
                 sec = sec_per_km.to_i % 60
                 "#{min}'#{format('%02d', sec)}\""
               else
                 "—"
               end
        time_s = a[:moving_time] ? format_time(a[:moving_time]) : "—"
        hr = a[:average_heartrate] ? a[:average_heartrate].round.to_s : "—"
        elev = a[:elevation_gain] ? format("%.0f", a[:elevation_gain]) : "—"
        speed = a[:average_speed] ? format("%.2f", a[:average_speed] * 3.6) : "—"
        cat = a[:sport_category] || "?"
        name = a[:name] || "Activity"
        date = format_date(a[:start_date])
        safe_id = a[:run_id].gsub(/[^a-zA-Z0-9_-]/, "_")

        <<~HTML
          <!DOCTYPE html>
          <html lang="zh-CN">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <title>#{escape_html(name)} — Workouts</title>
            <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="" />
            <style>
              * { box-sizing: border-box; }
              body { margin: 0; padding: 0; background: #222; color: #eee; font-family: -apple-system,BlinkMacSystemFont,sans-serif; }
              #map { width: 100%; height: 50vh; }
              .info { max-width: 600px; margin: 1rem auto; padding: 0 1rem; }
              .info h2 { margin: 0 0 0.5rem; font-size: 1.1rem; }
              .info .meta { color: #888; font-size: 0.85rem; margin-bottom: 1rem; }
              .info-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 0.5rem; }
              .info-item { background: #2a2a2a; padding: 0.5rem; border-radius: 6px; text-align: center; }
              .info-item .val { font-size: 1.2rem; font-weight: bold; color: #4DD2FF; display: block; }
              .info-item .lbl { font-size: 0.7rem; color: #888; }
              .back { display: inline-block; margin: 1rem; color: #4DD2FF; text-decoration: none; font-size: 0.85rem; }
              .back:hover { text-decoration: underline; }
              @media (max-width: 767px) {
                #map { height: 40vh; }
                .info-grid { grid-template-columns: 1fr 1fr; }
              }
            </style>
          </head>
          <body>
            <a href="index.html" class="back">← 返回主页</a>
            <div id="map"></div>
            <div class="info">
              <h2>#{escape_html(name)}</h2>
              <div class="meta">#{date} · #{cat}</div>
              <div class="info-grid">
                <div class="info-item"><span class="val">#{dist_km}</span><span class="lbl">距离 (km)</span></div>
                <div class="info-item"><span class="val">#{pace}</span><span class="lbl">配速</span></div>
                <div class="info-item"><span class="val">#{time_s}</span><span class="lbl">运动时间</span></div>
                <div class="info-item"><span class="val">#{speed}</span><span class="lbl">均速 (km/h)</span></div>
                <div class="info-item"><span class="val">#{hr}</span><span class="lbl">平均心率</span></div>
                <div class="info-item"><span class="val">#{elev}</span><span class="lbl">爬升 (m)</span></div>
              </div>
              <p style="font-size:0.7rem;color:#555;text-align:center;margin-top:1rem">
                Map tiles: © <a href="https://carto.com/">CARTO</a> · Data: © <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> contributors
              </p>
            </div>
            <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>
            <script>
              var points = #{points_json};
              if (points.length > 0) {
                var map = L.map('map').setView(points[0], 13);
                L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
                  attribution: '&copy; <a href="https://carto.com/">CARTO</a>, &copy; <a href="https://openstreetmap.org/copyright">OSM</a>',
                  maxZoom: 19
                }).addTo(map);
                var polyline = L.polyline(points, { color: '#4DD2FF', weight: 3, opacity: 0.8 }).addTo(map);
                map.fitBounds(polyline.getBounds().pad(0.1));
              }
            </script>
          </body>
          </html>
        HTML
      end

      def format_date(str)
        return "?" unless str
        Time.parse(str).strftime("%Y-%m-%d") rescue str[0..9]
      end

      def format_time(seconds)
        return nil unless seconds
        h = seconds / 3600
        m = (seconds % 3600) / 60
        s = seconds % 60
        format("%d:%02d:%02d", h, m, s)
      end

      def escape_html(str)
        str.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
          .gsub("'", "&#39;")
      end
    end
  end
end
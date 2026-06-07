require "fileutils"
require "json"
require "time"

module Workouts
  module Export
    class Dashboard
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

        activities = load_activities
        return 0 if activities.empty?

        @stats = Analysis::Calculator.new(db: @db, activity_filter: @activity_filter).call

        write_json(activities)
        write_stats(@stats)
        write_index_html

        activities.size
      end

      private

      def load_activities
        ds = @db[:activities].order(Sequel.desc(:start_date))
        ds = ds.where(sport_category: @activity_filter) if @activity_filter
        ds.all
      end

      def write_json(activities)
        json = activities.map { |a| format_activity(a) }
        File.write(File.join(@output, "activities.json"), ::JSON.generate(json))
      end

      def write_stats(stats)
        File.write(File.join(@output, "stats.json"), ::JSON.generate(stats))
      end

      def format_activity(a)
        {
          run_id: a[:run_id],
          name: a[:name],
          source: a[:source],
          distance: a[:distance],
          moving_time: a[:moving_time],
          type: a[:sport_category],
          start_date: a[:start_date],
          average_heartrate: a[:average_heartrate],
          average_speed: a[:average_speed],
          elevation_gain: a[:elevation_gain],
          polyline: a[:summary_polyline],
        }
      end

      def write_index_html
        html = build_html
        File.write(File.join(@output, "index.html"), html)
      end

      def build_html
        years_range = "#{@stats[:yearly].first[:year]}-#{@stats[:yearly].last[:year]}"

        <<~HTML
          <!DOCTYPE html>
          <html lang="zh-CN">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Workouts</title>
            <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
            <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
            <script src="https://cdn.jsdelivr.net/npm/echarts@5.5.0/dist/echarts.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/echarts@5.5.0/theme/dark.js"></script>
            <style>
              * { box-sizing: border-box; margin: 0; padding: 0; }
              body { background: #1a1a2e; color: #e0e0e0; font-family: -apple-system,BlinkMacSystemFont,sans-serif; overflow: hidden; height: 100vh; }
              a { color: #4DD2FF; text-decoration: none; }

              #map-container { position: fixed; inset: 0; z-index: 0; }
              #map { width: 100%; height: 100%; }

              .overlay { position: fixed; z-index: 1; pointer-events: none; }
              .overlay > * { pointer-events: auto; }

              .ol-tl { top: 12px; left: 12px; display: flex; flex-direction: column; gap: 6px; }
              .ol-tr { top: 12px; right: 12px; display: flex; flex-direction: column; gap: 6px; align-items: flex-end; }

              .brand { font-size: 0.85rem; color: #888; letter-spacing: 1px; }
              .brand strong { color: #4DD2FF; font-weight: 700; }

              .year-pills { display: flex; gap: 4px; flex-wrap: wrap; }
              .year-pill { padding: 3px 10px; border-radius: 14px; border: 1px solid #2a2a4a; background: rgba(22,33,62,0.85); color: #888; cursor: pointer; font-size: 0.75rem; transition: all 0.15s; backdrop-filter: blur(4px); }
              .year-pill:hover { border-color: #4DD2FF; color: #4DD2FF; }
              .year-pill.active { background: #4DD2FF; color: #1a1a2e; border-color: #4DD2FF; font-weight: 600; }
              .month-chip { padding: 3px 10px; border-radius: 14px; border: 1px solid #4ECDC4; background: rgba(78,205,196,0.15); color: #4ECDC4; cursor: pointer; font-size: 0.75rem; display: inline-flex; align-items: center; gap: 4px; }
              .month-chip:hover { background: rgba(78,205,196,0.25); }

              .legend-toggle { display: flex; background: rgba(22,33,62,0.85); border-radius: 8px; border: 1px solid #2a2a4a; overflow: hidden; backdrop-filter: blur(4px); }
              .legend-btn { padding: 4px 12px; font-size: 0.7rem; color: #888; cursor: pointer; border: none; background: transparent; transition: all 0.15s; }
              .legend-btn:hover { color: #ccc; }
              .legend-btn.active { background: #4DD2FF; color: #1a1a2e; font-weight: 600; }
              .legend-btn:first-child { border-right: 1px solid #2a2a4a; }

              .speed-legend { display: flex; gap: 0; border-radius: 6px; overflow: hidden; height: 8px; margin-top: 4px; }
              .speed-legend span { flex: 1; }
              .sl-blue { background: #4A90D9; }
              .sl-green { background: #50C878; }
              .sl-yellow { background: #FFD700; }
              .sl-red { background: #FF4500; }

              @keyframes spin { to { transform: rotate(360deg); } }

              .drawer { position: fixed; bottom: 0; left: 0; right: 0; z-index: 2; transform: translateY(calc(100% - 52px)); transition: transform 0.3s ease-out; will-change: transform; }
              .drawer.open { transform: translateY(0); }

              .drawer-handle { height: 16px; display: flex; justify-content: center; align-items: center; cursor: pointer; background: #16213e; border-radius: 12px 12px 0 0; border: 1px solid #2a2a4a; border-bottom: none; padding: 2px 0; }
              .drawer-handle .bar { width: 32px; height: 3px; border-radius: 2px; background: #444; }
              .drawer-handle:hover .bar { background: #4DD2FF; }

              .drawer-collapsed { height: 34px; display: flex; align-items: center; padding: 0 10px; gap: 6px; background: #16213e; border-left: 1px solid #2a2a4a; border-right: 1px solid #2a2a4a; }
              .stat-pill { font-size: 0.72rem; color: #888; white-space: nowrap; display: flex; align-items: center; gap: 3px; }
              .stat-pill strong { color: #fff; font-weight: 600; }
              .stat-pill .delta { display: inline; font-size: 0.65rem; margin: 0; }
              .stat-pill .delta.up { color: #4ECDC4; }
              .stat-pill .delta.down { color: #FF6B6B; }
              .spacer { flex: 1; }
              .icon-btn { background: transparent; border: 1px solid #2a2a4a; color: #888; border-radius: 6px; padding: 4px 8px; font-size: 0.85rem; cursor: pointer; transition: all 0.15s; line-height: 1; }
              .icon-btn:hover { border-color: #4DD2FF; color: #4DD2FF; }

              .drawer-body { height: 45vh; max-height: 480px; background: #16213e; border-left: 1px solid #2a2a4a; border-right: 1px solid #2a2a4a; display: none; flex-direction: column; }
              .drawer.open .drawer-body { display: flex; }

              .drawer-tabs { display: flex; border-bottom: 1px solid #2a2a4a; flex-shrink: 0; }
              .drawer-tab { padding: 8px 16px; font-size: 0.8rem; color: #888; cursor: pointer; border-bottom: 2px solid transparent; transition: all 0.15s; background: transparent; border-top: none; border-left: none; border-right: none; }
              .drawer-tab:hover { color: #ccc; }
              .drawer-tab.active { color: #4DD2FF; border-bottom-color: #4DD2FF; }
              .drawer-tab .badge { font-size: 0.65rem; color: #666; margin-left: 4px; }

              .drawer-panel { display: none; flex: 1; overflow-y: auto; overscroll-behavior: contain; }
              .drawer-panel.active { display: block; }
              .drawer-panel::-webkit-scrollbar { width: 5px; }
              .drawer-panel::-webkit-scrollbar-track { background: transparent; }
              .drawer-panel::-webkit-scrollbar-thumb { background: #2a2a4a; border-radius: 3px; }

              .act-item { display: grid; grid-template-columns: auto 1fr auto; gap: 10px; padding: 9px 14px; border-bottom: 1px solid #222; cursor: pointer; transition: background 0.12s; align-items: center; min-height: 48px; }
              .act-item:hover { background: #0f3460; }
              .act-item.active { background: #1a3a6a; }
              .act-item.hover { background: #1a3a6a; box-shadow: inset 3px 0 0 #4DD2FF; }
              .act-item .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
              .act-item .act-name { font-size: 0.82rem; color: #ccc; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
              .act-item .act-name .src-badge { font-size: 0.6rem; padding: 1px 5px; border-radius: 3px; margin-left: 5px; color: #888; background: #0f3460; }
              .act-item .act-date { font-size: 0.7rem; color: #666; }
              .act-item .act-meta { text-align: right; font-size: 0.72rem; color: #888; white-space: nowrap; }
              .act-item .act-meta .dist { color: #4DD2FF; font-weight: 600; }

              .list-controls { display: flex; gap: 6px; padding: 6px 14px; border-bottom: 1px solid #2a2a4a; align-items: center; flex-wrap: wrap; }
              .list-controls .sort-btn { background: transparent; border: 1px solid #2a2a4a; color: #888; border-radius: 4px; padding: 2px 8px; font-size: 0.7rem; cursor: pointer; }
              .list-controls .sort-btn:hover { border-color: #4DD2FF; color: #4DD2FF; }
              .list-controls .sort-btn.active { border-color: #4DD2FF; color: #4DD2FF; }
              .list-controls .count { font-size: 0.7rem; color: #666; margin-left: auto; }

              .filter-grid { padding: 12px 14px; display: flex; flex-direction: column; gap: 10px; }
              .filter-row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
              .filter-row label { font-size: 0.72rem; color: #888; min-width: 40px; }
              .filter-row select, .filter-row input { background: #0f3460; color: #e0e0e0; border: 1px solid #2a2a4a; border-radius: 5px; padding: 5px 10px; font-size: 0.8rem; outline: none; }
              .filter-row select:focus, .filter-row input:focus { border-color: #4DD2FF; }
              .filter-row input[type="text"] { flex: 1; min-width: 120px; }
              .filter-row input[type="number"] { width: 56px; }
              .filter-row .hint { font-size: 0.7rem; color: #666; }

              .insight { font-size: 0.78rem; color: #aaa; padding: 6px 14px; background: #0f3460; border-radius: 6px; margin: 0 14px 8px 14px; line-height: 1.5; text-align: center; }
              .insight em { color: #4DD2FF; font-style: normal; }

              .detail-overlay { display: none; position: fixed; inset: 0; z-index: 3; background: rgba(0,0,0,0.5); justify-content: center; align-items: flex-end; }
              .detail-overlay.open { display: flex; }
              .detail-panel { background: #16213e; border-radius: 16px 16px 0 0; max-width: 600px; width: 100%; max-height: 80vh; overflow-y: auto; padding: 1.2rem 1.2rem 2rem; border-top: 1px solid #2a2a4a; animation: slideUp 0.3s ease-out; }
              @keyframes slideUp { from { transform: translateY(100%); } to { transform: translateY(0); } }
              .detail-panel .close { float: right; font-size: 1.4rem; cursor: pointer; color: #888; line-height: 1; }
              .detail-panel .close:hover { color: #fff; }
              .detail-panel h2 { font-size: 1.05rem; margin-bottom: 2px; }
              .detail-panel .meta { color: #888; font-size: 0.78rem; margin-bottom: 0.8rem; }
              .detail-panel .grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 6px; }
              .detail-panel .grid .item { background: #0f3460; padding: 6px; border-radius: 6px; text-align: center; }
              .detail-panel .grid .item .v { font-size: 1rem; font-weight: 700; color: #4DD2FF; display: block; }
              .detail-panel .grid .item .l { font-size: 0.65rem; color: #888; }
              #detail-map { width: 100%; height: 180px; border-radius: 8px; margin-top: 0.8rem; }

              .charts-overlay { display: none; position: fixed; inset: 0; z-index: 4; background: rgba(0,0,0,0.6); justify-content: center; align-items: center; }
              .charts-overlay.open { display: flex; }
              .charts-panel { background: #16213e; border-radius: 16px; max-width: 520px; width: 92%; max-height: 85vh; overflow-y: auto; padding: 1.2rem; border: 1px solid #2a2a4a; }
              .charts-panel .close { float: right; font-size: 1.4rem; cursor: pointer; color: #888; line-height: 1; }
              .charts-panel .close:hover { color: #fff; }
              .charts-panel h3 { font-size: 0.9rem; color: #888; margin-bottom: 8px; }
              #chart { width: 100%; height: 240px; }
              #chart-small { width: 100%; height: 200px; }

              .empty { padding: 2rem; text-align: center; color: #666; font-size: 0.85rem; }

              ::-webkit-scrollbar { width: 5px; }
              ::-webkit-scrollbar-track { background: transparent; }
              ::-webkit-scrollbar-thumb { background: #2a2a4a; border-radius: 3px; }

              @media (max-width: 640px) {
                .drawer-body { height: 55vh; }
                .detail-panel .grid { grid-template-columns: 1fr 1fr; }
                .charts-panel { width: 96%; padding: 0.8rem; }
                .year-pill { font-size: 0.7rem; padding: 2px 8px; }
                .ol-tl { top: 8px; left: 8px; }
                .ol-tr { top: 8px; right: 8px; }
                .stat-pill { font-size: 0.68rem; }
              }
            </style>
          </head>
          <body>
            <div id="map-container"><div id="map"></div></div>

            <div class="overlay ol-tl">
              <div class="brand"><strong>Workouts</strong> #{years_range}</div>
              <div class="year-pills" id="year-pills"></div>
            </div>

            <div class="overlay ol-tr">
              <div class="legend-toggle">
                <button class="legend-btn active" data-mode="speed" onclick="setColorMode('speed')">速度</button>
                <button class="legend-btn" data-mode="type" onclick="setColorMode('type')">类型</button>
              </div>
              <div class="speed-legend" id="speed-legend"><span class="sl-blue"></span><span class="sl-green"></span><span class="sl-yellow"></span><span class="sl-red"></span></div>
            </div>

            <div class="drawer" id="app-drawer">
              <div class="drawer-handle" onclick="toggleDrawer()"><div class="bar"></div></div>
              <div class="drawer-collapsed">
                <span class="stat-pill"><strong id="pill-count">0</strong>次</span>
                <span class="stat-pill"><strong id="pill-dist">0</strong>km <span class="delta" id="pill-delta-dist"></span></span>
                <span class="stat-pill"><strong id="pill-time">0</strong>h <span class="delta" id="pill-delta-time"></span></span>
                <span class="stat-pill"><strong id="pill-elev">0</strong>m</span>
                <span class="spacer"></span>
                <button class="icon-btn" onclick="openCharts()" title="图表">&#x1F4CA;</button>
                <button class="icon-btn" onclick="toggleDrawer()" title="展开">&#x25B2;</button>
              </div>
              <div class="drawer-body">
                <div class="drawer-tabs">
                  <button class="drawer-tab active" data-tab="list" onclick="switchTab('list')">活动列表 <span class="badge" id="list-badge"></span></button>
                  <button class="drawer-tab" data-tab="filters" onclick="switchTab('filters')">筛选</button>
                </div>
                <div class="drawer-panel active" id="panel-list">
                  <div class="list-controls">
                    <button class="sort-btn active" data-sort="date" onclick="setSort('date')">日期</button>
                    <button class="sort-btn" data-sort="dist" onclick="setSort('dist')">距离</button>
                    <button class="sort-btn" data-sort="time" onclick="setSort('time')">时间</button>
                    <span class="count" id="list-count"></span>
                  </div>
                  <div id="list-body"></div>
                </div>
                <div class="drawer-panel" id="panel-filters">
                  <div class="insight" id="insight"></div>
                  <div class="filter-grid">
                    <div class="filter-row">
                      <label>类型</label>
                      <select id="filter-type"><option value="all">全部</option></select>
                    </div>
                    <div class="filter-row">
                      <label>来源</label>
                      <select id="filter-source"><option value="all">全部</option></select>
                    </div>
                    <div class="filter-row">
                      <label>距离</label>
                      <input type="number" id="filter-dist-min" placeholder="0" min="0" step="0.5" value="">
                      <span style="color:#444">—</span>
                      <input type="number" id="filter-dist-max" placeholder="&infin;" min="0" step="0.5" value="">
                      <span style="color:#888;font-size:0.7rem">km</span>
                    </div>
                    <div class="filter-row">
                      <label>搜索</label>
                      <input type="text" id="filter-search" placeholder="活动名称...">
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="detail-overlay" id="detail-overlay">
              <div class="detail-panel">
                <span class="close" id="detail-close">&times;</span>
                <h2 id="detail-name"></h2>
                <div class="meta"><span id="detail-date"></span> · <span id="detail-type"></span></div>
                <div class="grid">
                  <div class="item"><span class="v" id="detail-dist"></span><span class="l">距离 (km)</span></div>
                  <div class="item"><span class="v" id="detail-pace"></span><span class="l">配速</span></div>
                  <div class="item"><span class="v" id="detail-time"></span><span class="l">运动时间</span></div>
                  <div class="item"><span class="v" id="detail-speed"></span><span class="l">均速 (km/h)</span></div>
                  <div class="item"><span class="v" id="detail-hr"></span><span class="l">平均心率</span></div>
                  <div class="item"><span class="v" id="detail-elev"></span><span class="l">爬升 (m)</span></div>
                </div>
                <div id="detail-map"></div>
              </div>
            </div>

            <div class="charts-overlay" id="charts-overlay">
              <div class="charts-panel">
                <span class="close" id="charts-close">&times;</span>
                <h3>月运动距离</h3>
                <div id="chart"></div>
                <h3 style="margin-top:12px">运动类型分布</h3>
                <div id="chart-small"></div>
              </div>
            </div>

            <div style="display:none"><a href="activities.json">JSON</a> · <a href="stats.json">Stats</a> · Generated by Workouts CLI</div>

            <script>
            'use strict';

              function decodePolyline(encoded) {
                if (!encoded) return [];
                var points = [];
                var index = 0, lat = 0, lng = 0;
                while (index < encoded.length) {
                  var b, shift = 0, result = 0;
                  do { b = encoded.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
                  var dlat = (result & 1) ? ~(result >> 1) : (result >> 1); lat += dlat;
                  shift = 0; result = 0;
                  do { b = encoded.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
                  var dlng = (result & 1) ? ~(result >> 1) : (result >> 1); lng += dlng;
                  points.push([lat * 1e-5, lng * 1e-5]);
                }
                return points;
              }

              function fmtDate(d) { return d ? d.slice(0,10) : '?'; }
              function fmtYear(d) { return d ? d.slice(0,4) : '?'; }
              function fmtTime(s) { if (!s) return '—'; var h = Math.floor(s/3600), m = Math.floor((s%3600)/60); return h > 0 ? h+'h'+String(m).padStart(2,'0') : m+'min'; }
              function fmtPace(a) { if (!a || !a.moving_time || !a.distance || a.distance < 1) return '—'; var spk = a.moving_time / (a.distance / 1000); return Math.floor(spk/60)+"'" + String(Math.floor(spk%60)).padStart(2,'0')+'"'; }
              function fmtSpeed(a) { if (!a || !a.average_speed) return '—'; return (a.average_speed * 3.6).toFixed(1); }
              function distKm(a) { return a.distance ? (a.distance / 1000) : 0; }

              var CAT_COLORS = { run: '#4DD2FF', walk: '#4ECDC4', ride: '#FF6B6B', hike: '#FFD93D' };
              function typeColor(t) { return CAT_COLORS[t] || '#888'; }

              function speedColor(speedMs) {
                var s = (speedMs || 0) * 3.6;
                if (s < 3) return '#4A90D9';
                if (s < 6) return '#50C878';
                if (s < 9) return '#FFD700';
                return '#FF4500';
              }

              function traceColor(a, mode) {
                if (mode === 'type') return typeColor(a.type);
                return speedColor(a.average_speed);
              }

              var state = { activities: [], stats: null, filtered: [], map: null, chart: null, chartSmall: null, activeId: null, chartReady: false, monthFilter: null, sortBy: 'date', sortDesc: true, polylineMap: {}, drawerOpen: false, colorMode: 'speed' };

    function init() {
      Promise.all([
        fetch('activities.json').then(function(r) {
          if (!r.ok) throw new Error('fetch activities.json: ' + r.status);
          return r.json();
        }),
        fetch('stats.json').then(function(r) {
          if (!r.ok) throw new Error('fetch stats.json: ' + r.status);
          return r.json();
        })
      ]).then(function(results) {
        state.activities = results[0];
        state.stats = results[1];
        var stats = results[1];
        initFilters(stats);
        try {
          state.map = L.map('map', { zoomControl: true, attributionControl: false }).setView([30, 110], 4);
          L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
            maxZoom: 19
          }).addTo(state.map);
        } catch(e) { console.error('Map init:', e); }
        applyFilters();
      }).catch(function(e) {
        console.error('Dashboard init error:', e);
      });
    }

              function initFilters(stats) {
                var years = {};
                var types = {};
                var sources = {};
                state.activities.forEach(function(a) {
                  var y = fmtYear(a.start_date);
                  if (y !== '?') years[y] = (years[y] || 0) + 1;
                  if (a.type) types[a.type] = (types[a.type] || 0) + 1;
                  if (a.source) sources[a.source] = (sources[a.source] || 0) + 1;
                });
                var pills = document.getElementById('year-pills');
                var allBtn = document.createElement('button');
                allBtn.className = 'year-pill active';
                allBtn.textContent = '全部';
                allBtn.dataset.year = 'all';
                allBtn.onclick = function() { setYear('all'); };
                pills.appendChild(allBtn);
                Object.keys(years).sort().forEach(function(y) {
                  var btn = document.createElement('button');
                  btn.className = 'year-pill';
                  btn.textContent = y;
                  btn.dataset.year = y;
                  btn.onclick = function() { setYear(y); };
                  pills.appendChild(btn);
                });

                var typeSel = document.getElementById('filter-type');
                Object.keys(types).sort().forEach(function(t) {
                  var opt = document.createElement('option');
                  opt.value = t; opt.textContent = t + ' (' + types[t] + ')';
                  typeSel.appendChild(opt);
                });
                var srcSel = document.getElementById('filter-source');
                Object.keys(sources).sort().forEach(function(s) {
                  var opt = document.createElement('option');
                  opt.value = s; opt.textContent = s + ' (' + sources[s] + ')';
                  srcSel.appendChild(opt);
                });

                typeSel.onchange = applyFilters;
                srcSel.onchange = applyFilters;
                document.getElementById('filter-search').oninput = applyFilters;
              }

              function setYear(y) {
                document.querySelectorAll('.year-pill').forEach(function(b) { b.classList.remove('active'); });
                var target = document.querySelector('.year-pill[data-year="' + y + '"]');
                if (target) target.classList.add('active');
                state.monthFilter = null;
                applyFilters();
              }

              function getFilters() {
                var activePill = document.querySelector('.year-pill.active');
                var distMin = parseFloat(document.getElementById('filter-dist-min').value) || 0;
                var distMax = parseFloat(document.getElementById('filter-dist-max').value) || Infinity;
                return {
                  year: activePill ? activePill.dataset.year : 'all',
                  type: document.getElementById('filter-type').value,
                  source: document.getElementById('filter-source').value,
                  search: document.getElementById('filter-search').value.toLowerCase(),
                  month: state.monthFilter,
                  distMin: distMin,
                  distMax: distMax
                };
              }

              function applyFilters() {
                var f = getFilters();
                state.filtered = state.activities.filter(function(a) {
                  if (f.year !== 'all' && fmtYear(a.start_date) !== f.year) return false;
                  if (f.type !== 'all' && a.type !== f.type) return false;
                  if (f.source !== 'all' && a.source !== f.source) return false;
                  if (f.month && (!a.start_date || a.start_date.indexOf(f.month) !== 0)) return false;
                  if (f.search) {
                    var name = (a.name || '').toLowerCase();
                    if (name.indexOf(f.search) === -1) return false;
                  }
                  var dk = distKm(a);
                  if (dk < f.distMin || dk > f.distMax) return false;
                  return true;
                });
                state.filtered.sort(function(a, b) {
                  var va, vb;
                  if (state.sortBy === 'date') {
                    va = a.start_date || ''; vb = b.start_date || '';
                    return state.sortDesc ? (va < vb ? 1 : va > vb ? -1 : 0) : (va < vb ? -1 : va > vb ? 1 : 0);
                  } else if (state.sortBy === 'dist') {
                    va = a.distance || 0; vb = b.distance || 0;
                    return state.sortDesc ? vb - va : va - vb;
                  } else {
                    va = a.moving_time || 0; vb = b.moving_time || 0;
                    return state.sortDesc ? vb - va : va - vb;
                  }
                });
                renderMonthChip();
                renderStats();
                renderChart();
                renderChartSmall();
                renderMap();
                renderList();
              }

              function setSort(field) {
                if (state.sortBy === field) { state.sortDesc = !state.sortDesc; }
                else { state.sortBy = field; state.sortDesc = true; }
                document.querySelectorAll('.sort-btn').forEach(function(b) {
                  b.classList.toggle('active', b.dataset.sort === field);
                });
                applyFilters();
              }

              function clearMonthFilter() {
                state.monthFilter = null;
                applyFilters();
              }

              function renderMonthChip() {
                var container = document.getElementById('year-pills');
                var existing = container.querySelector('.month-chip');
                if (existing) existing.remove();
                if (state.monthFilter) {
                  var chip = document.createElement('span');
                  chip.className = 'month-chip';
                  chip.innerHTML = state.monthFilter + ' <span class="x" onclick="clearMonthFilter()">&times;</span>';
                  chip.onclick = clearMonthFilter;
                  container.appendChild(chip);
                }
              }

              function renderInsight(count, dist, time, elev) {
                var el = document.getElementById('insight');
                var msgs = [];
                var activePill = document.querySelector('.year-pill.active');
                var year = activePill ? activePill.dataset.year : 'all';

                if (year !== 'all' && state.stats && state.stats.yearly) {
                  var y = parseInt(year);
                  var prevYr = null, thisYr = null;
                  state.stats.yearly.forEach(function(yr) {
                    if (yr.year === y) thisYr = yr;
                    if (yr.year === y - 1) prevYr = yr;
                  });
                  if (thisYr && prevYr && thisYr.count > prevYr.count * 1.5) {
                    msgs.push(year + '年已运动<em>' + thisYr.count + '次</em>，是' + (y-1) + '年的' + Math.round(thisYr.count/prevYr.count) + '倍');
                  }
                  if (thisYr && prevYr && prevYr.count > 0 && thisYr.distance_km > prevYr.distance_km * 2) {
                    msgs.push('总距离<em>' + thisYr.distance_km.toFixed(0) + 'km</em>，已超过去年全年总和');
                  }
                }

                if (state.stats && state.stats.streaks && state.stats.streaks.all_time > 7) {
                  msgs.push('最长连续运动 <em>' + state.stats.streaks.all_time + '天</em>');
                }

                if (state.monthFilter && state.stats && state.stats.monthly) {
                  var ym = state.monthFilter;
                  var thisMonth = null;
                  state.stats.monthly.forEach(function(m) {
                    var mk = m.year + '-' + String(m.month).padStart(2,'0');
                    if (mk === ym) thisMonth = m;
                  });
                  if (thisMonth) {
                    msgs.push(ym + '月度距离 <em>' + thisMonth.distance_km.toFixed(0) + 'km</em>，' + thisMonth.count + '次活动');
                  }
                }

                if (msgs.length === 0) { el.textContent = ''; return; }
                el.innerHTML = msgs.join(' \u00B7 ');
              }

              function renderStats() {
                var acts = state.filtered;
                var count = acts.length;
                var dist = 0, time = 0, elev = 0;
                acts.forEach(function(a) {
                  dist += a.distance || 0;
                  time += a.moving_time || 0;
                  elev += a.elevation_gain || 0;
                });
                document.getElementById('pill-count').textContent = count;
                document.getElementById('pill-dist').textContent = (dist / 1000).toFixed(0);
                document.getElementById('pill-time').textContent = (time / 3600).toFixed(1);
                document.getElementById('pill-elev').textContent = elev.toFixed(0);
                document.getElementById('list-count').textContent = count + ' 项';
                document.getElementById('list-badge').textContent = count;

                renderDeltas(count, dist, time, elev);
                renderInsight(count, dist, time, elev);
              }

              function renderDeltas(count, dist, time, elev) {
                var activePill = document.querySelector('.year-pill.active');
                var year = activePill ? activePill.dataset.year : null;
                var prev = null;
                if (year && year !== 'all' && state.stats && state.stats.yearly) {
                  var y = parseInt(year);
                  state.stats.yearly.forEach(function(yr) {
                    if (yr.year === y - 1) prev = yr;
                  });
                }
                var items = [
                  { id: 'count', val: count, elId: 'delta-count' },
                  { id: 'dist', val: dist / 1000, elId: 'delta-dist' },
                  { id: 'time', val: time / 3600, elId: 'delta-time' },
                  { id: 'elev', val: elev, elId: 'delta-elev' }
                ];
                items.forEach(function(s) {
                  var el = document.getElementById(s.elId);
                  if (!el) return;
                  if (!prev) {
                    var comp = compareToPrevYear(s.id, s.val);
                    if (comp) { showDelta(el, comp.val, comp.pct); return; }
                    el.textContent = ''; return;
                  }
                  var prevVal = s.id === 'count' ? prev.count : s.id === 'dist' ? prev.distance_km : s.id === 'time' ? prev.moving_time_h : null;
                  if (prevVal != null && prevVal > 0) showDelta(el, s.val - prevVal, ((s.val - prevVal) / prevVal) * 100);
                  else el.textContent = '';
                });
              }

              function compareToPrevYear(metric, val) {
                if (!state.stats || !state.stats.yearly || state.stats.yearly.length < 2) return null;
                var years = state.stats.yearly;
                var prev = years[years.length - 2];
                var activePill = document.querySelector('.year-pill.active');
                var year = activePill ? activePill.dataset.year : 'all';
                if (year !== 'all') return null;
                var prevVal = metric === 'count' ? prev.count : metric === 'dist' ? prev.distance_km : metric === 'time' ? prev.moving_time_h : null;
                if (prevVal == null || prevVal <= 0) return null;
                return { val: val - prevVal, pct: ((val - prevVal) / prevVal) * 100 };
              }

              function showDelta(el, diff, pct) {
                if (!el) return;
                if (Math.abs(diff) < 0.01) { el.textContent = ''; return; }
                var arrow = diff > 0 ? '\u25B2' : '\u25BC';
                var cls = diff > 0 ? 'up' : 'down';
                var absPct = Math.abs(pct).toFixed(0);
                el.className = 'delta ' + cls;
                el.textContent = arrow + ' ' + absPct + '%';
              }

              function renderList() {
                var body = document.getElementById('list-body');
                var html = '';
                state.filtered.forEach(function(a) {
                  var c = state.colorMode === 'speed' ? speedColor(a.average_speed) : typeColor(a.type);
                  var d = distKm(a);
                  html += '<div class="act-item" data-id="' + escAttr(a.run_id) + '">';
                  html += '<span class="dot" style="background:' + c + '"></span>';
                  html += '<div><div class="act-name">' + escHtml(a.name || '') + '<span class="src-badge">' + escHtml(a.source || '') + '</span></div>';
                  html += '<div class="act-date">' + fmtDate(a.start_date) + '</div></div>';
                  html += '<div class="act-meta"><span class="dist">' + d.toFixed(1) + '</span> km<br>' + fmtTime(a.moving_time) + '</div>';
                  html += '</div>';
                });
                body.innerHTML = html || '<div class="empty">没有匹配的活动</div>';
                body.onclick = function(e) {
                  var item = e.target.closest('.act-item');
                  if (item) showActivity(item.dataset.id);
                };
                body.onmouseover = function(e) {
                  var item = e.target.closest('.act-item');
                  if (item) highlightMap(item.dataset.id);
                };
                body.onmouseout = function(e) {
                  var item = e.target.closest('.act-item');
                  if (item) unhighlightMap();
                };
              }

              function highlightMap(id) {
                Object.keys(state.polylineMap).forEach(function(k) {
                  state.polylineMap[k].setStyle({ weight: 1.5, opacity: 0.15 });
                });
                var line = state.polylineMap[id];
                if (line) line.setStyle({ weight: 3.5, opacity: 1, color: '#4DD2FF' });
              }
              function unhighlightMap() {
                Object.keys(state.polylineMap).forEach(function(k) {
                  state.polylineMap[k].setStyle({ weight: 1.5, opacity: 0.5 });
                });
              }

              function setColorMode(mode) {
                state.colorMode = mode;
                document.querySelectorAll('.legend-btn').forEach(function(b) {
                  b.classList.toggle('active', b.dataset.mode === mode);
                });
                renderMap();
                renderList();
              }

              function toggleDrawer() {
                state.drawerOpen = !state.drawerOpen;
                document.getElementById('app-drawer').classList.toggle('open', state.drawerOpen);
                setTimeout(function() { if (state.map) state.map.invalidateSize(); }, 350);
              }

              function switchTab(tab) {
                document.querySelectorAll('.drawer-tab').forEach(function(t) { t.classList.toggle('active', t.dataset.tab === tab); });
                document.querySelectorAll('.drawer-panel').forEach(function(p) { p.classList.toggle('active', p.id === 'panel-' + tab); });
                if (tab === 'chart') {
                  setTimeout(function() {
                    if (state.chart) state.chart.resize();
                    if (state.chartSmall) state.chartSmall.resize();
                  }, 100);
                }
              }

              function openCharts() {
                document.getElementById('charts-overlay').classList.add('open');
                if (!state.chartReady) {
                  try {
                    state.chart = echarts.init(document.getElementById('chart'), 'dark');
                    state.chartSmall = echarts.init(document.getElementById('chart-small'), 'dark');
                    state.chartReady = true;
                  } catch(e) { console.error('ECharts init:', e); }
                }
                setTimeout(function() {
                  if (state.chart) state.chart.resize();
                  if (state.chartSmall) state.chartSmall.resize();
                }, 150);
              }
              function closeCharts() {
                document.getElementById('charts-overlay').classList.remove('open');
              }

              function openDetail() { document.getElementById('detail-overlay').classList.add('open'); }
              function closeDetail() {
                document.getElementById('detail-overlay').classList.remove('open');
                if (state.detailMap) { state.detailMap.remove(); state.detailMap = null; }
              }

              function renderChart() {
                if (!state.chart) return;
                var byMonth = {};
                state.filtered.forEach(function(a) {
                  if (!a.start_date) return;
                  var m = a.start_date.slice(0,7);
                  byMonth[m] = (byMonth[m] || 0) + distKm(a);
                });
                var months = Object.keys(byMonth).sort();
                var data = months.map(function(m) { return +byMonth[m].toFixed(1); });
                var option = {
                  tooltip: { trigger: 'axis', formatter: function(p) { return p[0].axisValue + '<br/>' + p[0].value.toFixed(1) + ' km'; } },
                  grid: { left: 50, right: 16, top: 20, bottom: 30 },
                  xAxis: { type: 'category', data: months, axisLabel: { fontSize: 10, color: '#666' } },
                  yAxis: { type: 'value', name: 'km', nameTextStyle: { fontSize: 10, color: '#666' }, axisLabel: { fontSize: 10, color: '#666' }, splitLine: { lineStyle: { color: '#2a2a4a' } } },
                  series: [{ type: 'bar', data: data, itemStyle: { color: '#4DD2FF', borderRadius: [4,4,0,0] }, barMaxWidth: 32 }]
                };
                state.chart.setOption(option, true);
                if (!state.chartReady) {
                  state.chart.on('click', function(p) {
                    if (!p || !p.dataIndex) return;
                    var axis = state.chart.getOption().xAxis[0];
                    var m = axis ? axis.data[p.dataIndex] : null;
                    if (!m) return;
                    state.monthFilter = (state.monthFilter === m) ? null : m;
                    applyFilters();
                  });
                  state.chartReady = true;
                }
              }

              function renderChartSmall() {
                if (!state.chartSmall) return;
                var byType = {};
                state.filtered.forEach(function(a) {
                  var t = a.type || 'other';
                  byType[t] = (byType[t] || 0) + distKm(a);
                });
                var total = Object.values(byType).reduce(function(s, v) { return s + v; }, 0) || 1;
                var data = Object.keys(byType).sort().map(function(t) {
                  return { name: t, value: +byType[t].toFixed(1) };
                });
                var option = {
                  tooltip: { trigger: 'item', formatter: function(p) { return p.name + '<br/>' + p.value.toFixed(1) + ' km (' + (p.value/total*100).toFixed(1) + '%)'; } },
                  series: [{
                    type: 'pie', radius: ['40%', '70%'], center: ['50%', '50%'],
                    data: data,
                    itemStyle: { borderRadius: 4 },
                    label: { color: '#888', fontSize: 11, formatter: function(p) { return p.name; } },
                    labelLine: { lineStyle: { color: '#2a2a4a' } },
                    color: ['#4DD2FF','#4ECDC4','#FF6B6B','#FFD93D','#888']
                  }]
                };
                state.chartSmall.setOption(option, true);
              }

              function renderMap() {
                Object.keys(state.polylineMap).forEach(function(id) { state.map.removeLayer(state.polylineMap[id]); });
                state.polylineMap = {};
                if (state.filtered.length === 0) return;
                var allPoints = [];
                var maxLines = 500;
                var acts = state.filtered.slice(0, maxLines);
                acts.forEach(function(a) {
                  if (!a.polyline) return;
                  var pts = decodePolyline(a.polyline);
                  if (pts.length < 2) return;
                  var color = state.colorMode === 'speed' ? speedColor(a.average_speed) : typeColor(a.type);
                  var yr = parseInt((a.start_date || '').slice(0,4));
                  var opacity = yr ? Math.max(0.12, 1 - (new Date().getFullYear() - yr) * 0.12) : 0.4;
                  var line = L.polyline(pts, { color: color, weight: 2, opacity: opacity });
                  line.bindTooltip((a.name || '') + ' — ' + distKm(a).toFixed(1) + 'km', { direction: 'top' });
                  line.on('click', function() { showActivity(a.run_id); });
                  line.on('mouseover', function() { highlightList(a.run_id); });
                  line.on('mouseout', function() { unhighlightList(); });
                  state.polylineMap[a.run_id] = line;
                  line.addTo(state.map);
                  allPoints = allPoints.concat(pts);
                });
                if (allPoints.length > 10) {
                  var lats = allPoints.map(function(p) { return p[0]; }).sort(function(a,b){return a-b;});
                  var lngs = allPoints.map(function(p) { return p[1]; }).sort(function(a,b){return a-b;});
                  var medLat = lats[Math.floor(lats.length/2)];
                  var medLng = lngs[Math.floor(lngs.length/2)];
                  var filtered = allPoints.filter(function(p) {
                    return Math.abs(p[0]-medLat) < 15 && Math.abs(p[1]-medLng) < 15;
                  });
                  var bounds = L.latLngBounds(filtered.length > 10 ? filtered : allPoints);
                  if (bounds.isValid()) { state.map.fitBounds(bounds.pad(0.05)); }
                }
              }

              function highlightList(id) {
                document.querySelectorAll('.act-item').forEach(function(el) { el.classList.remove('hover'); });
                var el = document.querySelector('.act-item[data-id="' + escAttr(id) + '"]');
                if (el) el.classList.add('hover');
              }
              function unhighlightList() {
                document.querySelectorAll('.act-item').forEach(function(el) { el.classList.remove('hover'); });
              }

              function showActivity(runId) {
                var a = state.activities.find(function(x) { return x.run_id === runId; });
                if (!a) return;
                if (state.drawerOpen) toggleDrawer();
                document.querySelectorAll('.act-item').forEach(function(el) { el.classList.remove('active'); });
                var el = document.querySelector('.act-item[data-id="' + runId.replace(/'/g,"\\'") + '"]');
                if (el) { el.classList.add('active'); el.scrollIntoView({ block: 'nearest' }); }

                document.getElementById('detail-name').textContent = a.name || '';
                document.getElementById('detail-date').textContent = fmtDate(a.start_date);
                document.getElementById('detail-type').textContent = a.type || '';
                document.getElementById('detail-dist').textContent = distKm(a).toFixed(2);
                document.getElementById('detail-pace').textContent = fmtPace(a);
                document.getElementById('detail-time').textContent = fmtTime(a.moving_time);
                document.getElementById('detail-speed').textContent = fmtSpeed(a);
                document.getElementById('detail-hr').textContent = a.average_heartrate ? a.average_heartrate.toFixed(0) : '—';
                document.getElementById('detail-elev').textContent = a.elevation_gain ? a.elevation_gain.toFixed(0) : '—';
                openDetail();

                var mapContainer = document.getElementById('detail-map');
                if (a.polyline && a.polyline.length > 0) {
                  if (state.detailMap) { state.detailMap.remove(); }
                  state.detailMap = L.map(mapContainer, { zoomControl: false }).setView([30, 110], 13);
                  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', { maxZoom: 19 }).addTo(state.detailMap);
                  var pts = decodePolyline(a.polyline);
                  if (pts.length >= 2) {
                    var line = L.polyline(pts, { color: '#4DD2FF', weight: 3, opacity: 0.8 }).addTo(state.detailMap);
                    state.detailMap.fitBounds(line.getBounds().pad(0.1));
                  }
                  setTimeout(function() { if (state.detailMap) state.detailMap.invalidateSize(); }, 150);
                }
              }

              document.getElementById('detail-close').onclick = closeDetail;
              document.getElementById('detail-overlay').onclick = function(e) {
                if (e.target === this) closeDetail();
              };
              document.getElementById('charts-close').onclick = closeCharts;
              document.getElementById('charts-overlay').onclick = function(e) {
                if (e.target === this) closeCharts();
              };
              document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') { closeDetail(); closeCharts(); }
              });

              function escHtml(s) {
                if (!s) return '';
                return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
              }
              function escAttr(s) {
                if (!s) return '';
                return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
              }

              init();
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end

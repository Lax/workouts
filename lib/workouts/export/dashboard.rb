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
              body { background: #1a1a2e; color: #e0e0e0; font-family: -apple-system,BlinkMacSystemFont,sans-serif; min-height: 100vh; }
              a { color: #4DD2FF; text-decoration: none; }
              a:hover { text-decoration: underline; }

              .header { background: linear-gradient(135deg, #16213e, #1a1a2e); padding: 1.5rem 1rem; text-align: center; border-bottom: 1px solid #2a2a4a; }
              .header h1 { font-size: 1.6rem; font-weight: 700; color: #4DD2FF; letter-spacing: 2px; }
              .header .subtitle { color: #666; font-size: 0.8rem; margin-top: 4px; }

              .container { max-width: 1200px; margin: 0 auto; padding: 1rem; }

              .stats-row { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 1rem; }
              .stat-card { background: #16213e; border-radius: 12px; padding: 1rem; text-align: center; border: 1px solid #2a2a4a; }
              .stat-card .num { font-size: 1.6rem; font-weight: 700; color: #4DD2FF; display: block; }
              .stat-card .label { font-size: 0.75rem; color: #888; margin-top: 4px; }
              .stat-card .num.active { color: #4ECDC4; }

              .filter-bar { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 1rem; padding: 0.75rem; background: #16213e; border-radius: 12px; border: 1px solid #2a2a4a; }
              .filter-bar select, .filter-bar input { background: #0f3460; color: #e0e0e0; border: 1px solid #2a2a4a; border-radius: 6px; padding: 6px 12px; font-size: 0.85rem; outline: none; }
              .filter-bar select:focus, .filter-bar input:focus { border-color: #4DD2FF; }
              .filter-bar select { cursor: pointer; min-width: 90px; }
              .filter-bar input[type="text"] { flex: 1; min-width: 150px; }
              .filter-bar .filter-label { color: #888; font-size: 0.75rem; margin-right: -4px; }
              .filter-bar .stat-hint { color: #4ECDC4; font-size: 0.8rem; margin-left: auto; white-space: nowrap; }

              .year-pills { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 1rem; }
              .year-pill { padding: 4px 14px; border-radius: 20px; border: 1px solid #2a2a4a; background: transparent; color: #888; cursor: pointer; font-size: 0.8rem; transition: all 0.2s; }
              .year-pill:hover { border-color: #4DD2FF; color: #4DD2FF; }
              .year-pill.active { background: #4DD2FF; color: #1a1a2e; border-color: #4DD2FF; font-weight: 600; }

              .main-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 1rem; }
              .chart-box { background: #16213e; border-radius: 12px; padding: 1rem; border: 1px solid #2a2a4a; min-height: 320px; }
              .chart-box .chart-title { font-size: 0.85rem; color: #888; margin-bottom: 8px; }
              #chart { width: 100%; height: 300px; }
              #chart-small { width: 100%; height: 200px; }

              .map-box { background: #16213e; border-radius: 12px; padding: 0; border: 1px solid #2a2a4a; overflow: hidden; min-height: 320px; }
              #map { width: 100%; height: 320px; }

              .list-box { background: #16213e; border-radius: 12px; border: 1px solid #2a2a4a; margin-bottom: 1rem; }
              .list-header { display: flex; justify-content: space-between; align-items: center; padding: 0.75rem 1rem; border-bottom: 1px solid #2a2a4a; }
              .list-header span { font-size: 0.8rem; color: #888; }
              .list-header .count { color: #4DD2FF; font-weight: 600; }
              .list-body { max-height: 500px; overflow-y: auto; }
              .list-body::-webkit-scrollbar { width: 6px; }
              .list-body::-webkit-scrollbar-track { background: #0f3460; }
              .list-body::-webkit-scrollbar-thumb { background: #2a2a4a; border-radius: 3px; }
              .act-item { display: grid; grid-template-columns: auto 1fr auto; gap: 12px; padding: 10px 16px; border-bottom: 1px solid #222; cursor: pointer; transition: background 0.15s; align-items: center; }
              .act-item:hover { background: #0f3460; }
              .act-item.active { background: #1a3a6a; }
              .act-item .act-date { font-size: 0.75rem; color: #666; white-space: nowrap; min-width: 80px; }
              .act-item .act-name { font-size: 0.85rem; color: #ccc; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
              .act-item .act-name .src-badge { display: inline-block; font-size: 0.6rem; padding: 1px 6px; border-radius: 3px; margin-left: 6px; color: #888; background: #0f3460; }
              .act-item .act-meta { text-align: right; font-size: 0.75rem; color: #888; white-space: nowrap; }
              .act-item .act-meta .dist { color: #4DD2FF; font-weight: 600; }
              .act-item .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }

              .modal-overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.7); z-index: 1000; justify-content: center; align-items: center; }
              .modal-overlay.show { display: flex; }
              .modal { background: #16213e; border-radius: 16px; max-width: 600px; width: 90%; max-height: 80vh; overflow-y: auto; padding: 1.5rem; border: 1px solid #2a2a4a; position: relative; }
              .modal .close { position: absolute; top: 12px; right: 16px; font-size: 1.5rem; cursor: pointer; color: #888; }
              .modal .close:hover { color: #fff; }
              .modal h2 { font-size: 1.1rem; margin-bottom: 4px; }
              .modal .meta { color: #888; font-size: 0.8rem; margin-bottom: 1rem; }
              .modal .grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
              .modal .grid .item { background: #0f3460; padding: 8px; border-radius: 8px; text-align: center; }
              .modal .grid .item .v { font-size: 1.1rem; font-weight: 700; color: #4DD2FF; display: block; }
              .modal .grid .item .l { font-size: 0.7rem; color: #888; }
              #modal-map { width: 100%; height: 250px; border-radius: 8px; margin-top: 1rem; }

              .footer { text-align: center; padding: 1rem; color: #444; font-size: 0.7rem; }
              .footer a { color: #555; }

              @media (max-width: 768px) {
                .stats-row { grid-template-columns: repeat(2, 1fr); }
                .main-grid { grid-template-columns: 1fr; }
                .filter-bar .stat-hint { display: none; }
                .modal .grid { grid-template-columns: 1fr 1fr; }
              }
            </style>
          </head>
          <body>
            <div class="header">
              <h1>Workouts</h1>
              <div class="subtitle">#{years_range}</div>
            </div>
            <div class="container">
              <div class="stats-row" id="stats-row">
                <div class="stat-card"><span class="num" id="stat-count">0</span><span class="label">总运动</span></div>
                <div class="stat-card"><span class="num" id="stat-dist">0</span><span class="label">总距离 (km)</span></div>
                <div class="stat-card"><span class="num" id="stat-time">0</span><span class="label">总时长 (h)</span></div>
                <div class="stat-card"><span class="num" id="stat-elev">0</span><span class="label">总爬升 (m)</span></div>
              </div>

              <div class="year-pills" id="year-pills"></div>

              <div class="filter-bar">
                <span class="filter-label">类型</span>
                <select id="filter-type"><option value="all">全部</option></select>
                <span class="filter-label">来源</span>
                <select id="filter-source"><option value="all">全部</option></select>
                <input type="text" id="filter-search" placeholder="搜索活动名称...">
                <span class="stat-hint" id="filter-hint"></span>
              </div>

              <div class="main-grid">
                <div class="chart-box">
                  <div class="chart-title">月运动距离</div>
                  <div id="chart"></div>
                </div>
                <div class="chart-box">
                  <div class="chart-title">运动类型分布</div>
                  <div id="chart-small"></div>
                </div>
              </div>

              <div class="map-box">
                <div id="map"></div>
              </div>

              <div class="list-box">
                <div class="list-header">
                  <span>活动列表</span>
                  <span class="count" id="list-count">0</span>
                </div>
                <div class="list-body" id="list-body"></div>
              </div>
            </div>

            <div class="modal-overlay" id="modal">
              <div class="modal">
                <span class="close" id="modal-close">&times;</span>
                <h2 id="modal-name"></h2>
                <div class="meta"><span id="modal-date"></span> · <span id="modal-type"></span></div>
                <div class="grid">
                  <div class="item"><span class="v" id="modal-dist"></span><span class="l">距离 (km)</span></div>
                  <div class="item"><span class="v" id="modal-pace"></span><span class="l">配速</span></div>
                  <div class="item"><span class="v" id="modal-time"></span><span class="l">运动时间</span></div>
                  <div class="item"><span class="v" id="modal-speed"></span><span class="l">均速 (km/h)</span></div>
                  <div class="item"><span class="v" id="modal-hr"></span><span class="l">平均心率</span></div>
                  <div class="item"><span class="v" id="modal-elev"></span><span class="l">爬升 (m)</span></div>
                </div>
                <div id="modal-map"></div>
              </div>
            </div>

            <div class="footer">
              <a href="activities.json">JSON</a> · <a href="stats.json">Stats</a> · Generated by Workouts CLI
            </div>

            <script>
            (function() {
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
              function catColor(c) { return '#4DD2FF'; }

              var CAT_COLORS = { run: '#4DD2FF', walk: '#4ECDC4', ride: '#FF6B6B', hike: '#FFD93D' };
              var SRC_COLORS = { keep: '#4DD2FF', strava: '#FF6B6B', igpsport: '#4ECDC4', xoss: '#FFD93D', xingzhe: '#FF9FF3' };
              function typeColor(t) { return CAT_COLORS[t] || '#888'; }
              function srcColor(s) { return SRC_COLORS[s] || '#888'; }

              var state = { activities: [], filtered: [], map: null, polylines: [], chart: null, chartSmall: null, activeId: null, chartReady: false, chartSmallReady: false };

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
        var stats = results[1];
        initFilters(stats);
        try {
          state.chart = echarts.init(document.getElementById('chart'), 'dark');
          state.chartSmall = echarts.init(document.getElementById('chart-small'), 'dark');
        } catch(e) { console.error('ECharts init:', e); }
        try {
          state.map = L.map('map', { zoomControl: true }).setView([30, 110], 4);
          L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
            attribution: '&copy; <a href="https://carto.com/">CARTO</a>',
            maxZoom: 19
          }).addTo(state.map);
        } catch(e) { console.error('Map init:', e); }
        applyFilters();
      }).catch(function(e) {
        console.error('Dashboard init error:', e);
        var el = document.getElementById('stats-row');
        if (el) el.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:2rem;color:#ff6b6b">Error loading data: ' + e.message + '</div>';
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
                applyFilters();
              }

              function getFilters() {
                var activePill = document.querySelector('.year-pill.active');
                return {
                  year: activePill ? activePill.dataset.year : 'all',
                  type: document.getElementById('filter-type').value,
                  source: document.getElementById('filter-source').value,
                  search: document.getElementById('filter-search').value.toLowerCase()
                };
              }

              function applyFilters() {
                var f = getFilters();
                state.filtered = state.activities.filter(function(a) {
                  if (f.year !== 'all' && fmtYear(a.start_date) !== f.year) return false;
                  if (f.type !== 'all' && a.type !== f.type) return false;
                  if (f.source !== 'all' && a.source !== f.source) return false;
                  if (f.search) {
                    var name = (a.name || '').toLowerCase();
                    if (name.indexOf(f.search) === -1) return false;
                  }
                  return true;
                });
                renderStats();
                renderChart();
                renderChartSmall();
                renderMap();
                renderList();
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
                document.getElementById('stat-count').textContent = count;
                document.getElementById('stat-dist').textContent = (dist / 1000).toFixed(0);
                document.getElementById('stat-time').textContent = (time / 3600).toFixed(1);
                document.getElementById('stat-elev').textContent = elev.toFixed(0);
                document.getElementById('list-count').textContent = count + ' 项';
                var hint = document.getElementById('filter-hint');
                hint.textContent = count + ' / ' + state.activities.length + ' 活动';
              }

              function renderList() {
                var body = document.getElementById('list-body');
                var html = '';
                state.filtered.forEach(function(a) {
                  var c = typeColor(a.type);
                  var d = distKm(a);
                  html += '<div class="act-item" data-id="' + escAttr(a.run_id) + '">';
                  html += '<span class="dot" style="background:' + c + '"></span>';
                  html += '<div><div class="act-name">' + escHtml(a.name || '') + '<span class="src-badge">' + escHtml(a.source || '') + '</span></div>';
                  html += '<div class="act-date">' + fmtDate(a.start_date) + '</div></div>';
                  html += '<div class="act-meta"><span class="dist">' + d.toFixed(1) + '</span> km<br>' + fmtTime(a.moving_time) + '</div>';
                  html += '</div>';
                });
                body.innerHTML = html || '<div style="padding:2rem;text-align:center;color:#666;">没有匹配的活动</div>';
                body.onclick = function(e) {
                  var item = e.target.closest('.act-item');
                  if (item) showActivity(item.dataset.id);
                };
              }

              function renderChart() {
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
                    var m = months[p.dataIndex];
                    setYear(m.slice(0,4));
                  });
                  state.chartReady = true;
                }
              }

              function renderChartSmall() {
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

              var mapPolylines = [];

              function renderMap() {
                mapPolylines.forEach(function(l) { state.map.removeLayer(l); });
                mapPolylines = [];
                if (state.filtered.length === 0) return;
                var allPoints = [];
                var maxLines = 500;
                var acts = state.filtered.slice(0, maxLines);
                acts.forEach(function(a) {
                  if (!a.polyline) return;
                  var pts = decodePolyline(a.polyline);
                  if (pts.length < 2) return;
                  var line = L.polyline(pts, {
                    color: typeColor(a.type),
                    weight: 1.5,
                    opacity: 0.5
                  });
                  line.bindTooltip((a.name || '') + ' — ' + distKm(a).toFixed(1) + 'km', { direction: 'top' });
                  line.on('click', function() { showActivity(a.run_id); });
                  mapPolylines.push(line);
                  line.addTo(state.map);
                  allPoints = allPoints.concat(pts);
                });
                if (allPoints.length > 0) {
                  var bounds = L.latLngBounds(allPoints);
                  if (bounds.isValid()) { state.map.fitBounds(bounds.pad(0.05)); }
                }
              }

              function showActivity(runId) {
                var a = state.activities.find(function(x) { return x.run_id === runId; });
                if (!a) return;
                document.querySelectorAll('.act-item').forEach(function(el) { el.classList.remove('active'); });
                var el = document.querySelector('.act-item[data-id="' + runId.replace(/'/g,"\\'") + '"]');
                if (el) { el.classList.add('active'); el.scrollIntoView({ block: 'nearest' }); }

                var modal = document.getElementById('modal');
                document.getElementById('modal-name').textContent = a.name || '';
                document.getElementById('modal-date').textContent = fmtDate(a.start_date);
                document.getElementById('modal-type').textContent = a.type || '';
                document.getElementById('modal-dist').textContent = distKm(a).toFixed(2);
                document.getElementById('modal-pace').textContent = fmtPace(a);
                document.getElementById('modal-time').textContent = fmtTime(a.moving_time);
                document.getElementById('modal-speed').textContent = fmtSpeed(a);
                document.getElementById('modal-hr').textContent = a.average_heartrate ? a.average_heartrate.toFixed(0) : '—';
                document.getElementById('modal-elev').textContent = a.elevation_gain ? a.elevation_gain.toFixed(0) : '—';
                modal.classList.add('show');

                var mapContainer = document.getElementById('modal-map');
                if (a.polyline && a.polyline.length > 0) {
                  if (state.modalMap) { state.modalMap.remove(); }
                  state.modalMap = L.map(mapContainer, { zoomControl: false }).setView([30, 110], 13);
                  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
                    attribution: '&copy; <a href="https://carto.com/">CARTO</a>', maxZoom: 19
                  }).addTo(state.modalMap);
                  var pts = decodePolyline(a.polyline);
                  if (pts.length >= 2) {
                    var line = L.polyline(pts, { color: '#4DD2FF', weight: 3, opacity: 0.8 }).addTo(state.modalMap);
                    state.modalMap.fitBounds(line.getBounds().pad(0.1));
                  }
                  setTimeout(function() { state.modalMap.invalidateSize(); }, 100);
                }
              }

              document.getElementById('modal-close').onclick = function() {
                document.getElementById('modal').classList.remove('show');
                if (state.modalMap) { state.modalMap.remove(); state.modalMap = null; }
              };
              document.getElementById('modal').onclick = function(e) {
                if (e.target === this) {
                  this.classList.remove('show');
                  if (state.modalMap) { state.modalMap.remove(); state.modalMap = null; }
                }
              };

              function escHtml(s) {
                if (!s) return '';
                return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
              }
              function escAttr(s) {
                if (!s) return '';
                return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
              }

              init();
            })();
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end

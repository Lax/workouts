RSpec.describe Workouts::Export::Dashboard do
  let(:db) do
    d = Sequel.sqlite
    d.create_table(:activities) do
      Integer :id, primary_key: true
      String :run_id, null: false, unique: true
      String :name; Float :distance; Integer :moving_time; Integer :elapsed_time
      String :sport_category, null: false, default: "run"; String :sport_type
      String :start_date; String :start_date_local; String :location_country
      String :summary_polyline, text: true
      Float :average_heartrate; Float :max_heartrate
      Float :average_cadence; Float :max_cadence; Float :average_power; Float :max_power
      Integer :calories; Float :average_temperature
      Float :average_speed; Float :elevation_gain
      String :source
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
    d
  end

  let(:output) { Dir.mktmpdir }
  subject(:dashboard) { described_class.new(db:, output:, activity_filter: nil) }

  before do
    now = Time.now.utc
    db[:activities].insert(
      run_id: "test_1", name: "Morning Run", distance: 5000,
      moving_time: 1500, sport_category: "run",
      start_date: "2024-06-15T01:00:00Z", start_date_local: "2024-06-15T09:00:00Z",
      source: "strava", created_at: now, updated_at: now,
      summary_polyline: "abc", average_heartrate: 145,
      average_speed: 3.33, elevation_gain: 50
    )
    db[:activities].insert(
      run_id: "test_2", name: "Afternoon Ride", distance: 20000,
      moving_time: 3600, sport_category: "ride",
      start_date: "2024-06-20T01:00:00Z", start_date_local: "2024-06-20T09:00:00Z",
      source: "garmin", created_at: now, updated_at: now,
      summary_polyline: "def", average_heartrate: 148,
      average_cadence: 82, average_power: 195,
      average_speed: 5.56, elevation_gain: 200
    )
  end

  after { FileUtils.rm_rf(output) }

  describe "#call" do
    it "returns activity count" do
      expect(dashboard.call).to eq(2)
    end

    it "writes activities.json" do
      dashboard.call
      path = File.join(output, "activities.json")
      expect(File.exist?(path)).to be true
      data = JSON.parse(File.read(path))
      expect(data.size).to eq(2)
    end

    it "writes stats.json" do
      dashboard.call
      path = File.join(output, "stats.json")
      expect(File.exist?(path)).to be true
      data = JSON.parse(File.read(path))
      expect(data).to have_key("summary")
      expect(data).to have_key("monthly")
      expect(data).to have_key("yearly")
      expect(data).to have_key("streaks")
      expect(data).to have_key("activity_types")
    end

    it "writes index.html" do
      dashboard.call
      path = File.join(output, "index.html")
      expect(File.exist?(path)).to be true
    end

    it "returns 0 for empty DB" do
      empty_db = Sequel.sqlite
      empty_db.create_table(:activities) do
        primary_key :id
        String :run_id
        String :start_date
        String :sport_category
      end
      d = described_class.new(db: empty_db, output: output)
      expect(d.call).to eq(0)
    end
  end

  describe "#format_activity" do
    it "includes all required fields" do
      a = dashboard.send(:format_activity, db[:activities].first)
      expect(a[:run_id]).to eq("test_1")
      expect(a[:name]).to eq("Morning Run")
      expect(a[:source]).to eq("strava")
      expect(a[:distance]).to eq(5000)
      expect(a[:type]).to eq("run")
      expect(a[:start_date]).to eq("2024-06-15T01:00:00Z")
      expect(a[:summary_polyline]).to eq("abc")
    end

    it "includes sensor fields" do
      a = dashboard.send(:format_activity, db[:activities].first)
      expect(a).to have_key(:average_heartrate)
      expect(a).to have_key(:max_heartrate)
      expect(a).to have_key(:average_cadence)
      expect(a).to have_key(:average_power)
      expect(a).to have_key(:calories)
      expect(a).to have_key(:average_temperature)
      expect(a).to have_key(:average_speed)
      expect(a).to have_key(:elevation_gain)
    end
  end

  describe "#build_html" do
    before { dashboard.send(:instance_variable_set, :@stats, Workouts::Analysis::Calculator.new(db:).call) }

    it "contains required DOM IDs" do
      html = dashboard.send(:build_html)
      %w[map app-drawer chart chart-small detail-overlay charts-overlay].each do |id|
        expect(html).to include(%(id="#{id}"))
      end
    end

    it "contains Leaflet CDN script" do
      html = dashboard.send(:build_html)
      expect(html).to include("leaflet@1.9.4")
    end

    it "contains ECharts CDN script" do
      html = dashboard.send(:build_html)
      expect(html).to include("echarts@5.5.0")
    end

    it "contains inline JS with use strict" do
      html = dashboard.send(:build_html)
      expect(html).to include("'use strict'")
    end

    it "contains speed and type legend buttons" do
      html = dashboard.send(:build_html)
      expect(html).to include("setColorMode('speed')")
      expect(html).to include("setColorMode('type')")
    end

    it "contains year pills container" do
      html = dashboard.send(:build_html)
      expect(html).to include('class="year-pills"')
    end

    it "contains drawer with handle" do
      html = dashboard.send(:build_html)
      expect(html).to include('class="drawer-handle"')
    end
  end

  describe "JS functions (node validation)" do
    let(:js_path) { File.join(output, "dashboard_test.js") }

    before do
      stats = Workouts::Analysis::Calculator.new(db:).call
      dashboard.send(:instance_variable_set, :@stats, stats)
      html = dashboard.send(:build_html)
      js = html.match(%r{<script>\s*(.*?)\s*</script>}m)[1]
      File.write(js_path, js)
    end

    def node_test(assertions)
      mock = <<~MOCK
        console.error = function(){};
        var store = {};
        global.localStorage = { getItem: function(k){ return store[k] || null; }, setItem: function(k,v){ store[k]=v; }, removeItem: function(k){ delete store[k]; } };
        var mockEl = function(){ return { textContent: '', innerHTML: '', className: '', classList: { toggle: function(){}, add: function(){}, remove: function(){} }, style: {}, appendChild: function(){}, remove: function(){}, addEventListener: function(){}, onclick: null, closest: function(){return null}, dataset: {}, scrollIntoView: function(){}, value: '' } };
        global.document = {
          documentElement: { dataset: {} },
          getElementById: function(){ return mockEl(); },
          querySelectorAll: function(){ return []; },
          querySelector: function(){ return null; },
          createElement: function(){ return mockEl(); },
          addEventListener: function(){},
          createTextNode: function(){ return {}; }
        };
        global.window = { matchMedia: function(){ return { matches: false, addListener: function(){} } } };
        global.L = { map: function(){ return { setView: function(){return this}, on: function(){return this}, remove: function(){}, invalidateSize: function(){}, scrollWheelZoom: { disable: function(){}, enable: function(){} }, dragging: { disable: function(){}, enable: function(){} }, touchZoom: { disable: function(){}, enable: function(){} }, fitBounds: function(){return this}, addLayer: function(){}, removeLayer: function(){}, getZoom: function(){return 6}, getBounds: function(){return {pad: function(){return this}}} }; }, control: { zoom: function(){ return { addTo: function(){} } } }, tileLayer: function(){ return { addTo: function(){} } }, polyline: function(){ return { bindTooltip: function(){return this}, on: function(){return this}, addTo: function(){return this}, setStyle: function(){}, getBounds: function(){return {pad: function(){return {}}}} }; }, latLngBounds: function(){ return { isValid: function(){return true}, pad: function(){return this} } } };
        global.echarts = { init: function(){ return { setOption: function(){}, on: function(){}, resize: function(){} } } };
        global.fetch = function(){ return Promise.resolve({ ok: true, json: function(){ return Promise.resolve([]) } }) };
        global.setTimeout = function(fn){ fn() };
      MOCK

      script = mock + "\n" + File.read(js_path) + "\n" + assertions
      test_file = File.join(output, "node_test.js")
      File.write(test_file, script)
      result = `node #{test_file} 2>&1`
      [result, $?]
    end

    it "passes syntax check" do
      result = `node -e "new Function(require('fs').readFileSync('#{js_path}','utf8'))" 2>&1`
      expect($?).to eq(0), "JS syntax error: #{result}"
    end

    it "decodePolyline returns [] for nil" do
      result, status = node_test("console.log(JSON.stringify(decodePolyline(null))); console.log(JSON.stringify(decodePolyline('')));")
      expect(status).to eq(0), "node error: #{result}"
      expect(result.split("\n")).to all(eq("[]"))
    end

    it "decodePolyline decodes known polyline" do
      assertions = <<~JS
        var pts = decodePolyline('_p~iF~ps|U_ulLnnqC');
        console.log(pts.length);
        console.log(pts[0][0].toFixed(1) + ',' + pts[0][1].toFixed(1));
        console.log(pts[1][0].toFixed(1) + ',' + pts[1][1].toFixed(1));
      JS
      result, status = node_test(assertions)
      expect(status).to eq(0), "node error: #{result}"
      lines = result.split("\n")
      expect(lines[0]).to eq("2")
      expect(lines[1]).to eq("38.5,-120.2")
      expect(lines[2]).to eq("40.7,-121.0")
    end

    it "fmtDate handles nil and valid input" do
      result, status = node_test("console.log(fmtDate(null)); console.log(fmtDate('2024-06-15T10:00:00Z'));")
      expect(status).to eq(0), "node error: #{result}"
      expect(result.split("\n")).to eq(["?", "2024-06-15"])
    end

    it "fmtTime handles nil, minutes, and hours" do
      result, status = node_test("console.log(fmtTime(null)); console.log(fmtTime(1500)); console.log(fmtTime(5400));")
      expect(status).to eq(0), "node error: #{result}"
      expect(result.split("\n")).to eq(["—", "25min", "1h30"])
    end

    it "fmtPace handles nil and valid activity" do
      result, status = node_test("console.log(fmtPace(null)); console.log(fmtPace({moving_time: 1500, distance: 5000}));")
      expect(status).to eq(0), "node error: #{result}"
      lines = result.split("\n")
      expect(lines[0]).to eq("—")
      expect(lines[1]).to eq("5'00\"")
    end

    it "speedColor maps speed ranges to colors" do
      result, status = node_test("console.log(speedColor(0)); console.log(speedColor(0.8)); console.log(speedColor(1.5)); console.log(speedColor(2.4));")
      expect(status).to eq(0), "node error: #{result}"
      lines = result.split("\n")
      expect(lines[0]).to eq("#4A90D9")
      expect(lines[1]).to eq("#4A90D9")
      expect(lines[2]).to eq("#50C878")
      expect(lines[3]).to eq("#FFD700")
    end

    it "typeColor falls back to #888 for unknown types" do
      result, status = node_test("console.log(typeColor('run')); console.log(typeColor('unknown'));")
      expect(status).to eq(0), "node error: #{result}"
      expect(result.split("\n")).to eq(["#4DD2FF", "#888"])
    end

    it "distKm returns 0 for nil distance" do
      result, status = node_test("console.log(distKm({})); console.log(distKm({distance: 5000}));")
      expect(status).to eq(0), "node error: #{result}"
      expect(result.split("\n")).to eq(["0", "5"])
    end

    it "escHtml escapes HTML special chars" do
      result, status = node_test("console.log(escHtml('<script> & \\\"quote\\\"'));")
      expect(status).to eq(0), "node error: #{result}"
      expect(result.strip).to eq("&lt;script&gt; &amp; &quot;quote&quot;")
    end

    it "escAttr escapes for attribute context" do
      result, status = node_test("console.log(escAttr(\"it's \\\"test\\\"\"));")
      expect(status).to eq(0), "node error: #{result}"
      expect(result.strip).to eq("it&#39;s &quot;test&quot;")
    end
  end
end

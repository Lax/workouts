RSpec.describe Workouts::Sync::AppleHealth do
  let(:tmpdir) { Dir.mktmpdir }
  let(:db) { create_test_db }
  let(:config) { {} }
  subject(:adapter) { described_class.new(config:, db:) }

  before do
    allow(adapter).to receive(:raw_dir).and_return(File.join(tmpdir, "raw"))
    allow(adapter).to receive(:std_dir).and_return(File.join(tmpdir, "std"))
  end

  after { FileUtils.rm_rf(tmpdir) }

  def create_test_db
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
      String :duplicate_info, text: true
      String :title, text: true
      String :source
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
    d
  end

  def create_test_zip(target_path, xml_path, gpx_path = nil)
    fixture_xml = File.read(xml_path)
    Zip::File.open(target_path, Zip::File::CREATE) do |zip|
      zip.get_output_stream("apple_health_export/export.xml") { |io| io.write(fixture_xml) }
      if gpx_path
        gpx_data = File.read(gpx_path)
        zip.get_output_stream("apple_health_export/workout-routes/route_2023-06-15_9.00am.gpx") { |io| io.write(gpx_data) }
      end
    end
  end

  describe "#known_source?" do
    it "matches Strava" do
      expect(adapter.send(:known_source?, "Strava")).to be true
    end

    it "matches Keep" do
      expect(adapter.send(:known_source?, "Keep for iOS")).to be true
    end

    it "matches iGPSPORT" do
      expect(adapter.send(:known_source?, "iGPSPORT")).to be true
    end

    it "matches XOSS" do
      expect(adapter.send(:known_source?, "XOSS Running")).to be true
    end

    it "matches XingZhe" do
      expect(adapter.send(:known_source?, "XingZhe")).to be true
    end

    it "matches Connect (Garmin)" do
      expect(adapter.send(:known_source?, "Connect")).to be true
    end

    it "allows Apple Watch" do
      expect(adapter.send(:known_source?, "Lax's Apple Watch")).to be false
    end

    it "allows iPhone" do
      expect(adapter.send(:known_source?, "iPhone")).to be false
    end

    it "handles nil" do
      expect(adapter.send(:known_source?, nil)).to be false
    end
  end

  describe "#parse_duration" do
    it "converts minutes to seconds" do
      expect(adapter.send(:parse_duration, "45.5", "min")).to eq(2730)
    end

    it "converts hours to seconds" do
      expect(adapter.send(:parse_duration, "1.5", "hour")).to eq(5400)
    end

    it "passes through seconds" do
      expect(adapter.send(:parse_duration, "120", "sec")).to eq(120)
    end
  end

  describe "#parse_temperature" do
    it "converts Fahrenheit to Celsius" do
      result = adapter.send(:parse_temperature, "68 degF")
      expect(result).to be_within(0.1).of(20.0)
    end

    it "passes through Celsius" do
      expect(adapter.send(:parse_temperature, "20 ℃")).to eq(20.0)
    end

    it "returns nil for empty input" do
      expect(adapter.send(:parse_temperature, "")).to be_nil
    end

    it "returns nil for nil input" do
      expect(adapter.send(:parse_temperature, nil)).to be_nil
    end
  end

  describe "#generate_run_id" do
    it "produces an 8-char hex string" do
      id = adapter.send(:generate_run_id, "Lax's Apple Watch", "2023-06-15 09:00:00 +0800", "2023-06-15 09:45:00 +0800")
      expect(id).to match(/\A[0-9a-f]{8}\z/)
    end

    it "is deterministic" do
      a = adapter.send(:generate_run_id, "Watch", "d1", "d2")
      b = adapter.send(:generate_run_id, "Watch", "d1", "d2")
      expect(a).to eq(b)
    end

    it "changes with different input" do
      a = adapter.send(:generate_run_id, "Watch", "d1", "d2")
      b = adapter.send(:generate_run_id, "Watch", "d1", "d3")
      expect(a).not_to eq(b)
    end
  end

  describe "#map_sport_type" do
    it "maps Running to run" do
      expect(adapter.send(:map_sport_type, "HKWorkoutActivityTypeRunning")).to eq("run")
    end

    it "maps Cycling to ride" do
      expect(adapter.send(:map_sport_type, "HKWorkoutActivityTypeCycling")).to eq("ride")
    end

    it "maps Walking to walk" do
      expect(adapter.send(:map_sport_type, "HKWorkoutActivityTypeWalking")).to eq("walk")
    end

    it "maps TraditionalStrengthTraining to workout" do
      expect(adapter.send(:map_sport_type, "HKWorkoutActivityTypeTraditionalStrengthTraining")).to eq("workout")
    end

    it "returns other for unknown" do
      expect(adapter.send(:map_sport_type, "HKWorkoutActivityTypeYoga")).to eq("workout")
    end
  end

  describe "#parse_hr_line" do
    it "parses Apple Watch HR line" do
      line = '<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Lax\'s Apple Watch" unit="count/min" startDate="2023-06-15 09:00:00 +0800" value="140"/>'
      hr = adapter.send(:parse_hr_line, line)
      expect(hr.time).to be_a(Time)
      expect(hr.value).to eq(140)
    end

    it "returns nil for non-matching line" do
      line = '<Record type="HKQuantityTypeIdentifierStepCount" value="100"/>'
      expect(adapter.send(:parse_hr_line, line)).to be_nil
    end
  end

  describe "#correlate_heart_rate" do
    before do
      adapter.instance_variable_set(:@heart_rate_index, [
        Workouts::Sync::AppleHealth::HeartRateRecord.new(time: Time.parse("2023-06-15 09:00:00 +0800"), value: 140),
        Workouts::Sync::AppleHealth::HeartRateRecord.new(time: Time.parse("2023-06-15 09:10:00 +0800"), value: 155),
        Workouts::Sync::AppleHealth::HeartRateRecord.new(time: Time.parse("2023-06-15 09:20:00 +0800"), value: 165),
        Workouts::Sync::AppleHealth::HeartRateRecord.new(time: Time.parse("2023-06-15 09:30:00 +0800"), value: 158),
        Workouts::Sync::AppleHealth::HeartRateRecord.new(time: Time.parse("2023-06-15 09:40:00 +0800"), value: 148),
        Workouts::Sync::AppleHealth::HeartRateRecord.new(time: Time.parse("2023-06-15 10:00:00 +0800"), value: 100),
      ])
    end

    it "returns avg and max within time window" do
      avg, max = adapter.send(:correlate_heart_rate, "2023-06-15 09:00:00 +0800", "2023-06-15 09:45:00 +0800")
      expect(avg).to be_within(0.1).of(153.2)
      expect(max).to eq(165)
    end

    it "returns nil pair when no overlap" do
      avg, max = adapter.send(:correlate_heart_rate, "2023-06-15 12:00:00 +0800", "2023-06-15 13:00:00 +0800")
      expect(avg).to be_nil
      expect(max).to be_nil
    end

    it "handles empty index" do
      adapter.instance_variable_set(:@heart_rate_index, [])
      avg, max = adapter.send(:correlate_heart_rate, "2023-06-15 09:00:00 +0800", "2023-06-15 09:45:00 +0800")
      expect(avg).to be_nil
      expect(max).to be_nil
    end
  end

  describe "#call" do
    context "when export.zip does not exist" do
      before do
        allow(adapter).to receive(:before_call).and_return(false)
        allow(adapter).to receive(:authenticate).and_return(true)
      end

      it "returns 0" do
        expect(adapter.call).to eq(0)
      end
    end

    context "with valid export data" do
      before do
        zip_path = File.join(tmpdir, "export.zip")
        create_test_zip(zip_path,
          "spec/fixtures/apple_health/export.xml",
          "spec/fixtures/apple_health/route.gpx")
        allow(adapter).to receive(:before_call).and_call_original
        stub_const("Workouts::Sync::AppleHealth::DEFAULT_ZIP_PATH", zip_path)
        adapter.instance_variable_set(:@zip_path, zip_path)
      end

      it "returns the number of synced activities" do
        result = adapter.call
        expect(result).to eq(2)
      end

      it "inserts activities into DB" do
        adapter.call
        expect(db[:activities].count).to eq(2)
      end

      it "creates DB records with correct source" do
        adapter.call
        db[:activities].each do |row|
          expect(row[:source]).to eq("apple_health")
        end
      end

      it "assigns correct sport_category" do
        adapter.call
        cats = db[:activities].order(:start_date).map { |r| r[:sport_category] }
        expect(cats).to contain_exactly("run", "workout")
      end

      it "generates valid run_id format" do
        adapter.call
        db[:activities].each do |row|
          expect(row[:run_id]).to match(/\Aapple_health_[0-9a-f]{8}\z/)
        end
      end

      it "writes L1 raw files" do
        adapter.call
        xml_files = Dir.glob(File.join(adapter.send(:raw_dir), "*.xml"))
        expect(xml_files.size).to eq(2)
      end

      it "writes GPX alongside L1 XML for GPS-enabled activity" do
        adapter.call
        gpx_files = Dir.glob(File.join(adapter.send(:raw_dir), "*.gpx"))
        expect(gpx_files.size).to eq(1)
        gpx = File.read(gpx_files.first)
        expect(gpx).to include("<gpx")
        expect(gpx).to include("trkpt")
      end

      it "GPX in L1 matches original fixture" do
        adapter.call
        gpx_file = Dir.glob(File.join(adapter.send(:raw_dir), "*.gpx")).first
        gpx = File.read(gpx_file)
        original = File.read("spec/fixtures/apple_health/route.gpx")
        expect(gpx.strip).to eq(original.strip)
      end

      it "writes L2 std files for GPS-enabled activity" do
        adapter.call
        std_files = Dir.glob(File.join(adapter.send(:std_dir), "*.json"))
        expect(std_files.size).to eq(1)
      end

      it "includes speed in L2 JSON for GPS points" do
        adapter.call
        std_file = Dir.glob(File.join(adapter.send(:std_dir), "*.json")).first
        pts = JSON.parse(File.read(std_file))
        expect(pts.first["speed"]).to be_a(Float)
        expect(pts.first["speed"]).to eq(3.5)
      end

      it "writes summary_polyline for GPS-enabled activity" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:summary_polyline]).not_to be_nil
      end

      it "sets elevation_gain from GPX" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:elevation_gain]).to be > 0
      end

      it "converts temperature to Celsius" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:average_temperature]).to be_within(0.1).of(20.0)
      end

      it "sets heart rate from correlated records" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:average_heartrate]).to be_within(0.1).of(153.2)
        expect(run[:max_heartrate]).to eq(165)
      end

      it "sets calories including active + basal" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:calories]).to eq(606)
      end

      it "sets average_speed from distance and moving_time" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:average_speed]).to be_within(0.01).of(3.85)
      end

      it "sets distance for running" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:distance]).to eq(10_500.0)
      end

      it "does not write distance for strength training" do
        adapter.call
        st = db[:activities].where(sport_category: "workout").first
        expect(st[:distance]).to be_nil
      end

      it "sets title with date and type label" do
        adapter.call
        run = db[:activities].where(sport_category: "run").first
        expect(run[:title]).to eq("2023-06-15 · Running")
      end

      it "sets heart rate to nil for strength training (no HR records overlap)" do
        adapter.call
        st = db[:activities].where(sport_category: "workout").first
        expect(st[:average_heartrate]).to be_nil
        expect(st[:max_heartrate]).to be_nil
      end

      it "sets calories for strength training including active + basal" do
        adapter.call
        st = db[:activities].where(sport_category: "workout").first
        expect(st[:calories]).to eq(215)
      end

      it "builds heart rate index during pending_ids" do
        adapter.pending_ids
        idx = adapter.instance_variable_get(:@heart_rate_index)
        expect(idx).not_to be_nil
        expect(idx.size).to eq(5)
        expect(idx.first.value).to eq(140)
        expect(idx.last.value).to eq(148)
      end

      it "is idempotent on second run" do
        adapter.call
        adapter2 = described_class.new(config: {}, db:)
        allow(adapter2).to receive(:raw_dir).and_return(File.join(tmpdir, "raw"))
        allow(adapter2).to receive(:std_dir).and_return(File.join(tmpdir, "std"))
        adapter2.instance_variable_set(:@zip_path, adapter.instance_variable_get(:@zip_path))
        expect(adapter2.call).to eq(0)
      end
    end
  end

  describe "#pending_ids" do
    let(:zip_path) { File.join(tmpdir, "export.zip") }

    before do
      create_test_zip(zip_path, "spec/fixtures/apple_health/export.xml")
      adapter.instance_variable_set(:@zip_path, zip_path)
    end

    it "returns only non-filtered activities" do
      ids = adapter.pending_ids
      expect(ids.size).to eq(2)
    end

    it "excludes Strava-sourced activities" do
      ids = adapter.pending_ids
      strava_ids = ids.select { |p| p[:source_name].to_s.match?(/Strava/i) }
      expect(strava_ids).to be_empty
    end

    it "includes run_id in each pending item" do
      ids = adapter.pending_ids
      ids.each do |p|
        expect(p[:run_id]).to match(/\A[0-9a-f]{8}\z/)
      end
    end

    it "includes route_paths when available" do
      ids = adapter.pending_ids
      run = ids.find { |p| p[:type] == "run" }
      expect(run[:route_paths]).not_to be_empty
    end

    it "includes stats hash" do
      ids = adapter.pending_ids
      run = ids.find { |p| p[:type] == "run" }
      expect(run[:stats]).to be_a(Hash)
      expect(run[:stats].keys).to include(/Distance/i)
    end

    it "includes metadata" do
      ids = adapter.pending_ids
      run = ids.find { |p| p[:type] == "run" }
      expect(run[:meta]["HKWeatherTemperature"]).to eq("68 degF")
    end
  end

  describe "#elevation_gain_from_points" do
    it "sums positive elevation changes" do
      points = [
        { ele: 5.0 }, { ele: 6.0 }, { ele: 7.0 }, { ele: 6.5 }, { ele: 8.0 }
      ]
      result = adapter.send(:elevation_gain_from_points, points)
      expect(result).to eq(3.5)
    end
  end

  describe "speed filtering" do
    it "keeps speeds >= 0.1 m/s" do
      expect(Workouts::Sync::AppleHealth::MIN_GPX_SPEED).to eq(0.1)
    end

    it "filters zero speed from GPX" do
      gpx = <<~GPX
        <?xml version="1.0"?>
        <gpx xmlns="http://www.topografix.com/GPX/1/1">
        <trk><trkseg>
        <trkpt lat="31.23" lon="121.47"><ele>5</ele><time>2023-06-15T09:00:00Z</time><extensions><speed>0.0</speed></extensions></trkpt>
        <trkpt lat="31.24" lon="121.48"><ele>6</ele><time>2023-06-15T09:05:00Z</time><extensions><speed>3.5</speed></extensions></trkpt>
        <trkpt lat="31.25" lon="121.49"><ele>7</ele><time>2023-06-15T09:10:00Z</time><extensions><speed>0.05</speed></extensions></trkpt>
        </trkseg></trk>
        </gpx>
      GPX
      gpx_file = File.join(tmpdir, "test.gpx")
      File.write(gpx_file, gpx)
      pts = adapter.send(:parse_gpx_file, gpx_file)
      speeds = pts.map { |p| p[:speed] }
      expect(speeds).to eq([nil, 3.5, nil])
    end
  end
end

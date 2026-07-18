require "tmpdir"
require "fileutils"
require "sequel"

RSpec.describe Workouts::Import::LocalFile do
  let(:db) do
    db = Sequel.sqlite("")
    db.create_table :activities do
      primary_key :id
      String :run_id, unique: true
      String :name
      Float :distance
      Integer :moving_time
      Integer :elapsed_time
      String :sport_category
      String :sport_type
      String :start_date
      String :start_date_local
      String :location_country
      String :summary_polyline
      Float :average_heartrate
      Float :average_speed
      Float :elevation_gain
      String :source
      DateTime :created_at
      DateTime :updated_at
    end
    db
  end

  let(:simple_gpx) { <<~GPX }
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
      <trk>
        <name>Morning Run</name>
        <trkseg>
          <trkpt lat="39.9087" lon="116.3975">
            <ele>50</ele>
            <time>2024-01-01T00:00:00Z</time>
          </trkpt>
          <trkpt lat="39.9090" lon="116.3980">
            <ele>52</ele>
            <time>2024-01-01T00:01:00Z</time>
          </trkpt>
          <trkpt lat="39.9095" lon="116.3985">
            <ele>55</ele>
            <time>2024-01-01T00:02:00Z</time>
          </trkpt>
        </trkseg>
      </trk>
    </gpx>
  GPX

  let(:multi_track_gpx) { <<~GPX }
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
      <trk>
        <name>First</name>
        <trkseg>
          <trkpt lat="39.91" lon="116.40"><ele>50</ele><time>2024-01-01T00:00:00Z</time></trkpt>
          <trkpt lat="39.92" lon="116.41"><ele>52</ele><time>2024-01-01T00:01:00Z</time></trkpt>
        </trkseg>
      </trk>
      <trk>
        <name>Second</name>
        <trkseg>
          <trkpt lat="40.71" lon="-74.00"><ele>10</ele><time>2024-01-02T00:00:00Z</time></trkpt>
          <trkpt lat="40.72" lon="-74.01"><ele>12</ele><time>2024-01-02T00:01:00Z</time></trkpt>
        </trkseg>
      </trk>
    </gpx>
  GPX

  let(:simple_tcx) { <<~TCX }
    <?xml version="1.0" encoding="UTF-8"?>
    <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
      <Activities>
        <Activity Sport="Running">
          <Notes>Morning Jog</Notes>
          <Lap StartTime="2024-01-01T00:00:00Z">
            <TotalTimeSeconds>600</TotalTimeSeconds>
            <DistanceMeters>1500</DistanceMeters>
            <Calories>120</Calories>
            <AverageHeartRateBpm><Value>145</Value></AverageHeartRateBpm>
            <Intensity>Active</Intensity>
            <Track>
              <Trackpoint>
                <Time>2024-01-01T00:00:00Z</Time>
                <Position><LatitudeDegrees>39.9087</LatitudeDegrees><LongitudeDegrees>116.3975</LongitudeDegrees></Position>
                <AltitudeMeters>50</AltitudeMeters>
                <HeartRateBpm><Value>130</Value></HeartRateBpm>
              </Trackpoint>
              <Trackpoint>
                <Time>2024-01-01T00:01:00Z</Time>
                <Position><LatitudeDegrees>39.9090</LatitudeDegrees><LongitudeDegrees>116.3980</LongitudeDegrees></Position>
                <AltitudeMeters>52</AltitudeMeters>
                <HeartRateBpm><Value>145</Value></HeartRateBpm>
              </Trackpoint>
              <Trackpoint>
                <Time>2024-01-01T00:02:00Z</Time>
                <Position><LatitudeDegrees>39.9095</LatitudeDegrees><LongitudeDegrees>116.3985</LongitudeDegrees></Position>
                <AltitudeMeters>55</AltitudeMeters>
                <HeartRateBpm><Value>150</Value></HeartRateBpm>
              </Trackpoint>
            </Track>
          </Lap>
        </Activity>
      </Activities>
    </TrainingCenterDatabase>
  TCX

  around do |example|
    Dir.mktmpdir("workouts_test") do |dir|
      @tmpdir = dir
      dirs = {
        "gpx" => File.join(dir, "import_gpx"),
        "fit" => File.join(dir, "import_fit"),
        "tcx" => File.join(dir, "import_tcx")
      }
      orig = Workouts::Import::LocalFile::IMPORT_DIRS
      Workouts::Import::LocalFile.send(:remove_const, :IMPORT_DIRS)
      Workouts::Import::LocalFile.const_set(:IMPORT_DIRS, dirs)
      example.run
      Workouts::Import::LocalFile.send(:remove_const, :IMPORT_DIRS)
      Workouts::Import::LocalFile.const_set(:IMPORT_DIRS, orig)
    end
  end

  def build_adapter(sources: ["gpx"], sport_override: nil)
    described_class.new(
      config: {}, db:,
      sources: sources,
      sport_override: sport_override
    )
  end

  def write_import_file(source, filename, content)
    dir = Workouts::Import::LocalFile::IMPORT_DIRS[source]
    FileUtils.mkdir_p(dir)
    path = File.join(dir, filename)
    File.write(path, content)
    path
  end

  describe "GPX import" do
    it "imports a single GPX file as one activity" do
      write_import_file("gpx", "test.gpx", simple_gpx)
      adapter = build_adapter
      count = adapter.call
      expect(count).to eq(1)
      expect(db[:activities].count).to eq(1)
      activity = db[:activities].first
      expect(activity[:distance]).to be > 0
      expect(activity[:source]).to eq("gpx")
    end

    it "imports multi-track GPX as separate activities" do
      write_import_file("gpx", "multi.gpx", multi_track_gpx)
      adapter = build_adapter
      count = adapter.call
      expect(count).to eq(2)
      expect(db[:activities].count).to eq(2)
    end

    it "overrides sport_category with --sport" do
      write_import_file("gpx", "test.gpx", simple_gpx)
      adapter = build_adapter(sport_override: "run")
      adapter.call
      activity = db[:activities].first
      expect(activity[:sport_category]).to eq("run")
    end

    it "skips duplicate file (same content) on re-import" do
      write_import_file("gpx", "test.gpx", simple_gpx)
      adapter = build_adapter
      expect(adapter.call).to eq(1)
      adapter2 = build_adapter
      expect(adapter2.call).to eq(0)
    end
  end

  describe "TCX import" do
    it "imports a TCX file as one activity" do
      write_import_file("tcx", "test.tcx", simple_tcx)
      adapter = build_adapter(sources: ["tcx"])
      count = adapter.call
      expect(count).to eq(1)
      activity = db[:activities].first
      expect(activity[:distance]).to eq(1500.0)
      expect(activity[:sport_category]).to eq("run")
    end
  end

  describe "FIT import" do
    let(:fit_fixture) { File.expand_path("../fixtures/igpsport/fit_sample.50279925.fit", __dir__) }

    it "imports a FIT file as one activity" do
      dest = File.join(Workouts::Import::LocalFile::IMPORT_DIRS["fit"], "test.fit")
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(fit_fixture, dest)
      adapter = build_adapter(sources: ["fit"])
      count = adapter.call
      expect(count).to eq(1)
      activity = db[:activities].first
      expect(activity[:distance]).to be > 0
    end
  end

  describe "edge cases" do
    it "returns 0 for empty directory" do
      dir = Workouts::Import::LocalFile::IMPORT_DIRS["gpx"]
      FileUtils.mkdir_p(dir)
      adapter = build_adapter
      expect(adapter.call).to eq(0)
    end

    it "returns 0 for missing directory" do
      adapter = build_adapter
      expect(adapter.call).to eq(0)
    end

    it "continues batch on corrupted file" do
      write_import_file("gpx", "good.gpx", simple_gpx)
      write_import_file("gpx", "bad.gpx", "not valid xml")
      adapter = build_adapter
      count = adapter.call
      expect(count).to eq(1)
      expect(db[:activities].count).to eq(1)
    end

    it "returns 0 for FIT file with no GPS" do
      dest = File.join(Workouts::Import::LocalFile::IMPORT_DIRS["fit"], "nogps.fit")
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.touch(dest)
      allow(Workouts::FIT::Decoder).to receive(:decode).and_return([])
      adapter = build_adapter(sources: ["fit"])
      expect(adapter.call).to eq(0)
    end
  end
end

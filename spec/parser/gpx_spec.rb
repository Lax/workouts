RSpec.describe Workouts::Parser::GPX do
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

  let(:gpx_with_hr) { <<~GPX }
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
      xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
      <trk>
        <name>HR Run</name>
        <trkseg>
          <trkpt lat="40.71" lon="-74.00">
            <ele>10</ele>
            <time>2024-06-01T08:00:00Z</time>
            <extensions>
              <gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr></gpxtpx:TrackPointExtension>
            </extensions>
          </trkpt>
          <trkpt lat="40.72" lon="-74.01">
            <ele>12</ele>
            <time>2024-06-01T08:00:05Z</time>
            <extensions>
              <gpxtpx:TrackPointExtension><gpxtpx:hr>150</gpxtpx:hr></gpxtpx:TrackPointExtension>
            </extensions>
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

  subject { described_class.new(source: "test") }

  it "parses a simple GPX file" do
    result = subject.call(simple_gpx)
    expect(result.length).to eq(1)
    expect(result[0][:name]).to eq("Morning Run")
    expect(result[0][:distance]).to be > 0
    expect(result[0][:sport_category]).to eq("other")
    expect(result[0][:start_date]).to eq("2024-01-01T00:00:00Z")
    expect(result[0][:source]).to eq("test")
  end

  it "extracts heart rate from extensions" do
    result = subject.call(gpx_with_hr)
    expect(result.length).to eq(1)
    expect(result[0][:average_heartrate]).to be_within(0.1).of(145.0)
  end

  it "generates a valid polyline" do
    result = subject.call(simple_gpx)
    expect(result[0][:summary_polyline]).not_to be_nil
    decoded = Workouts::Geo::Polyline.decode(result[0][:summary_polyline])
    expect(decoded.length).to be > 0
  end

  it "parses multiple tracks" do
    result = subject.call(multi_track_gpx)
    expect(result.length).to eq(2)
    expect(result[0][:name]).to eq("First")
    expect(result[1][:name]).to eq("Second")
  end

  it "handles empty GPX" do
    result = subject.call("<gpx xmlns='http://www.topografix.com/GPX/1/1'></gpx>")
    expect(result).to eq([])
  end

  it "computes elevation gain" do
    result = subject.call(simple_gpx)
    expect(result[0][:elevation_gain]).to be_within(0.1).of(5.0)
  end

  it "computes moving time" do
    result = subject.call(gpx_with_hr)
    expect(result[0][:moving_time]).to eq(5)
    expect(result[0][:elapsed_time]).to eq(5)
  end

  it "sets run_id based on start time" do
    result = subject.call(simple_gpx)
    expect(result[0][:run_id]).to match(/^gpx_20240101T/)
  end
end

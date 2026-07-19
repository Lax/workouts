RSpec.describe Workouts::Parser::GPX do
  subject(:parser) { described_class.new }

  let(:gpx_data) { <<~GPX }
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
      <trk>
        <name>Morning Run</name>
        <trkseg>
          <trkpt lat="31.2304" lon="121.4737">
            <ele>5.0</ele>
            <time>2023-06-15T09:00:00Z</time>
          </trkpt>
          <trkpt lat="31.2310" lon="121.4740">
            <ele>6.0</ele>
            <time>2023-06-15T09:05:00Z</time>
          </trkpt>
          <trkpt lat="31.2320" lon="121.4745">
            <ele>7.0</ele>
            <time>2023-06-15T09:10:00Z</time>
          </trkpt>
        </trkseg>
      </trk>
    </gpx>
  GPX

  describe "#call" do
    it "parses GPX and returns activities" do
      results = parser.call(gpx_data)
      expect(results).to be_an(Array)
      expect(results.size).to eq(1)
    end

    it "sets start_date and start_date_local to same UTC value" do
      results = parser.call(gpx_data)
      act = results.first
      expect(act[:start_date]).to eq("2023-06-15T09:00:00Z")
      expect(act[:start_date_local]).to eq("2023-06-15T09:00:00Z")
    end

    it "computes distance from GPS points" do
      results = parser.call(gpx_data)
      act = results.first
      expect(act[:distance]).to be_a(Float).and be > 0
    end

    it "sets sport_category to default (other)" do
      results = parser.call(gpx_data)
      expect(results.first[:sport_category]).to eq("other")
    end

    it "parses empty GPX gracefully" do
      empty = <<~GPX
        <?xml version="1.0"?>
        <gpx xmlns="http://www.topografix.com/GPX/1/1"></gpx>
      GPX
      expect(parser.call(empty)).to eq([])
    end
  end
end

RSpec.describe Workouts::Parser::TCX do
  subject(:parser) { described_class.new }

  let(:tcx_data) { <<~TCX }
    <?xml version="1.0" encoding="UTF-8"?>
    <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
      <Activities>
        <Activity Sport="Running">
          <Id>2023-06-15T09:00:00Z</Id>
          <Lap StartTime="2023-06-15T09:00:00Z">
            <TotalTimeSeconds>600.0</TotalTimeSeconds>
            <DistanceMeters>2000.0</DistanceMeters>
            <Calories>120</Calories>
            <Track>
              <Trackpoint>
                <Time>2023-06-15T09:00:00Z</Time>
                <Position>
                  <LatitudeDegrees>31.2304</LatitudeDegrees>
                  <LongitudeDegrees>121.4737</LongitudeDegrees>
                </Position>
                <AltitudeMeters>5.0</AltitudeMeters>
              </Trackpoint>
              <Trackpoint>
                <Time>2023-06-15T09:05:00Z</Time>
                <Position>
                  <LatitudeDegrees>31.2310</LatitudeDegrees>
                  <LongitudeDegrees>121.4740</LongitudeDegrees>
                </Position>
                <AltitudeMeters>6.0</AltitudeMeters>
              </Trackpoint>
              <Trackpoint>
                <Time>2023-06-15T09:10:00Z</Time>
                <Position>
                  <LatitudeDegrees>31.2320</LatitudeDegrees>
                  <LongitudeDegrees>121.4745</LongitudeDegrees>
                </Position>
                <AltitudeMeters>7.0</AltitudeMeters>
              </Trackpoint>
            </Track>
          </Lap>
        </Activity>
      </Activities>
    </TrainingCenterDatabase>
  TCX

  describe "#call" do
    it "parses TCX and returns activities" do
      results = parser.call(tcx_data)
      expect(results).to be_an(Array)
      expect(results.size).to eq(1)
    end

    it "sets start_date and start_date_local to same UTC value" do
      results = parser.call(tcx_data)
      act = results.first
      expect(act[:start_date]).to eq("2023-06-15T09:00:00Z")
      expect(act[:start_date_local]).to eq("2023-06-15T09:00:00Z")
    end

    it "computes distance from GPS points" do
      results = parser.call(tcx_data)
      act = results.first
      expect(act[:distance]).to be_a(Float).and be > 0
    end

    it "sets sport_category from Sport attribute" do
      results = parser.call(tcx_data)
      expect(results.first[:sport_category]).to eq("run")
    end

    it "handles empty TCX gracefully" do
      empty = <<~TCX
        <?xml version="1.0"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities></Activities>
        </TrainingCenterDatabase>
      TCX
      expect(parser.call(empty)).to eq([])
    end
  end
end

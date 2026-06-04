RSpec.describe Workouts::Parser::TCX do
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

  subject { described_class.new(source: "test") }

  it "parses a TCX activity" do
    result = subject.call(simple_tcx)
    expect(result.length).to eq(1)
    expect(result[0][:name]).to eq("Morning Jog")
    expect(result[0][:sport_category]).to eq("run")
    expect(result[0][:distance]).to eq(1500.0)
    expect(result[0][:average_heartrate]).to be_within(0.1).of(145.0)
  end

  it "extracts lap timing" do
    result = subject.call(simple_tcx)
    expect(result[0][:moving_time]).to eq(600)
    expect(result[0][:elapsed_time]).to eq(600)
  end

  it "normalizes sport type" do
    result = subject.call(simple_tcx)
    expect(result[0][:sport_category]).to eq("run")
    expect(result[0][:sport_type]).to eq("Running")
  end

  it "computes average speed" do
    result = subject.call(simple_tcx)
    expect(result[0][:average_speed]).to be_within(0.01).of(2.5)
  end

  it "generates a polyline from track points" do
    result = subject.call(simple_tcx)
    expect(result[0][:summary_polyline]).not_to be_nil
    decoded = Workouts::Geo::Polyline.decode(result[0][:summary_polyline])
    expect(decoded.length).to eq(3)
  end

  it "handles empty TCX" do
    result = subject.call("<TrainingCenterDatabase xmlns='http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2'><Activities/></TrainingCenterDatabase>")
    expect(result).to eq([])
  end

  it "computes elevation gain from track points" do
    result = subject.call(simple_tcx)
    expect(result[0][:elevation_gain]).to be_within(0.1).of(5.0)
  end
end

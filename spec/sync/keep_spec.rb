RSpec.describe Workouts::Sync::Keep do
  subject(:keep) { described_class.new(config: {}, db: nil) }

  describe "#extract_id" do
    it "extracts numeric part from compound ID" do
      expect(keep.send(:extract_id, "abc_123_rn")).to eq("123")
    end

    it "handles ID without underscore" do
      expect(keep.send(:extract_id, "simpleid")).to be_nil
    end

    it "returns nil for nil input" do
      expect(keep.send(:extract_id, nil)).to be_nil
    end

    it "extracts from three-part compound ID" do
      expect(keep.send(:extract_id, "57b47900_9223370326790482307_rn")).to eq("9223370326790482307")
    end
  end

  describe "#haversine_dist" do
    it "returns 0 for same point" do
      expect(keep.send(:haversine_dist, [0, 0], [0, 0])).to eq(0)
    end

    it "calculates distance along equator" do
      dist = keep.send(:haversine_dist, [0, 0], [0, 1])
      expect(dist).to be_within(500).of(111_195)
    end

    it "calculates north-south distance" do
      dist = keep.send(:haversine_dist, [0, 0], [1, 0])
      expect(dist).to be_within(500).of(111_195)
    end
  end

  describe "#total_distance_haversine" do
    it "returns 0 for empty points" do
      expect(keep.send(:total_distance_haversine, [])).to eq(0)
    end

    it "returns 0 for single point" do
      expect(keep.send(:total_distance_haversine, [[0, 0]])).to eq(0)
    end

    it "returns distance for two points" do
      dist = keep.send(:total_distance_haversine, [[0, 0], [0, 1]])
      expect(dist).to be_within(500).of(111_195)
    end

    it "returns cumulative distance for three points" do
      dist = keep.send(:total_distance_haversine, [[0, 0], [0, 1], [0, 2]])
      expect(dist).to be_within(1000).of(222_390)
    end
  end

  describe "#elevation_gain_from_points" do
    def pt(lat, lng, elev)
      [lat, lng, elev, nil, nil]
    end

    it "returns 0 for empty points" do
      expect(keep.send(:elevation_gain_from_points, [])).to eq(0)
    end

    it "returns 0 for single point" do
      expect(keep.send(:elevation_gain_from_points, [pt(0, 0, 100)])).to eq(0)
    end

    it "sums only positive elevation changes" do
      points = [pt(0, 0, 100), pt(0, 1, 150), pt(0, 2, 120)]
      expect(keep.send(:elevation_gain_from_points, points)).to eq(50)
    end

    it "handles nil elevations" do
      points = [pt(0, 0, nil), pt(0, 1, 100), pt(0, 2, nil)]
      expect(keep.send(:elevation_gain_from_points, points)).to eq(100)
    end
  end

  describe "#compute_avg_hr" do
    def pt(lat, lng, elev, time, hr)
      [lat, lng, elev, time, hr]
    end

    it "returns nil for empty points" do
      expect(keep.send(:compute_avg_hr, [])).to be_nil
    end

    it "returns average of heart rates" do
      points = [pt(0, 0, nil, nil, 140), pt(0, 1, nil, nil, 160)]
      expect(keep.send(:compute_avg_hr, points)).to eq(150)
    end

    it "ignores nil heart rates" do
      points = [pt(0, 0, nil, nil, 140), pt(0, 1, nil, nil, nil), pt(0, 2, nil, nil, 160)]
      expect(keep.send(:compute_avg_hr, points)).to eq(150)
    end
  end

  describe "#find_nearest_hr" do
    let(:hr_data) do
      [
        { "timestamp" => 100, "beatsPerMinute" => 140 },
        { "timestamp" => 200, "beatsPerMinute" => 150 },
        { "timestamp" => 300, "beatsPerMinute" => 160 }
      ]
    end
    let(:start_time) { 0 }

    it "returns exact matching HR" do
      expect(keep.send(:find_nearest_hr, hr_data, 100, start_time)).to eq(140)
    end

    it "returns nearest HR within threshold" do
      expect(keep.send(:find_nearest_hr, hr_data, 205, start_time)).to eq(150)
    end

    it "returns nil when no HR data" do
      expect(keep.send(:find_nearest_hr, [], 100, start_time)).to be_nil
    end

    it "returns nil when geo timestamp is nil" do
      expect(keep.send(:find_nearest_hr, hr_data, nil, start_time)).to be_nil
    end

    it "uses large timestamp normalization" do
      hr_data_large = [
        { "timestamp" => 1_700_000_000, "beatsPerMinute" => 140 }
      ]
      result = keep.send(:find_nearest_hr, hr_data_large, 1_700_000_100, start_time)
      expect(result).to eq(140)
    end

    it "returns nil when HR has non-positive value" do
      bad_hr = [{ "timestamp" => 100, "beatsPerMinute" => -1 }]
      expect(keep.send(:find_nearest_hr, bad_hr, 100, start_time)).to be_nil
    end
  end
end

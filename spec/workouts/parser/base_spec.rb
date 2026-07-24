RSpec.describe Workouts::Parser::Base do
  subject(:parser) { described_class.new(source: "test") }

  describe "#format_time" do
    it "returns nil for nil input" do
      expect(parser.send(:format_time, nil)).to be_nil
    end

    it "converts UTC time to ISO8601 with Z suffix" do
      t = Time.utc(2023, 6, 15, 9, 0, 0)
      expect(parser.send(:format_time, t)).to eq("2023-06-15T09:00:00Z")
    end

    it "forces UTC for time with offset" do
      t = Time.new(2023, 6, 15, 17, 0, 0, "+08:00")
      expect(parser.send(:format_time, t)).to eq("2023-06-15T09:00:00Z")
    end
  end

  describe "#format_time_local" do
    it "returns nil for nil input" do
      expect(parser.send(:format_time_local, nil)).to be_nil
    end

    it "preserves offset for time with non-UTC offset" do
      t = Time.new(2023, 6, 15, 17, 0, 0, "+08:00")
      result = parser.send(:format_time_local, t)
      expect(result).to eq("2023-06-15T17:00:00+08:00")
    end

    it "returns Z for UTC time" do
      t = Time.utc(2023, 6, 15, 9, 0, 0)
      result = parser.send(:format_time_local, t)
      expect(result).to eq("2023-06-15T09:00:00Z")
    end

    it "returns same as format_time for UTC time" do
      t = Time.utc(2023, 6, 15, 9, 0, 0)
      expect(parser.send(:format_time_local, t)).to eq(parser.send(:format_time, t))
    end

    it "differs from format_time for non-UTC time" do
      t = Time.new(2023, 6, 15, 17, 0, 0, "+08:00")
      local = parser.send(:format_time_local, t)
      utc = parser.send(:format_time, t)
      expect(local).not_to eq(utc)
      expect(local).to end_with("+08:00")
      expect(utc).to end_with("Z")
    end

    it "handles negative offset" do
      t = Time.new(2023, 6, 15, 5, 0, 0, "-04:00")
      result = parser.send(:format_time_local, t)
      expect(result).to eq("2023-06-15T05:00:00-04:00")
    end

    it "handles string input" do
      expect(parser.send(:format_time_local, "raw-string")).to eq("raw-string")
    end
  end

  describe "#normalize_sport_type" do
    it "delegates to SportMapper.canonicalize" do
      expect(Workouts::SportMapper).to receive(:canonicalize).with("Running").and_return("run")
      parser.send(:normalize_sport_type, "Running")
    end

    it "returns run for Running via alias" do
      expect(parser.send(:normalize_sport_type, "Running")).to eq("run")
    end

    it "returns hike for mountaineering via keyword" do
      expect(parser.send(:normalize_sport_type, "mountaineering")).to eq("hike")
    end

    it "returns swim for swiming via Levenshtein" do
      expect(parser.send(:normalize_sport_type, "swiming")).to eq("swim")
    end

    it "returns other for unrecognized input" do
      expect(parser.send(:normalize_sport_type, "skateboarding")).to eq("other")
    end

    it "returns other for nil" do
      expect(parser.send(:normalize_sport_type, nil)).to eq("other")
    end
  end

  describe "#build_activity_attrs" do
    it "uses format_time for start_date and format_time_local for start_date_local" do
      t = Time.new(2023, 6, 15, 17, 0, 0, "+08:00")
      data = {
        run_id: "test_1",
        name: "Test",
        distance: 10000,
        moving_time: 3600,
        elapsed_time: 3600,
        sport_category: "run",
        sport_type: "running",
        start_date: t,
        start_date_local: t,
        location_country: nil,
        summary_polyline: nil,
        average_heartrate: nil,
        elevation_gain: nil,
        source: "test"
      }
      attrs = parser.send(:build_activity_attrs, data)
      expect(attrs[:start_date]).to eq("2023-06-15T09:00:00Z")
      expect(attrs[:start_date_local]).to eq("2023-06-15T17:00:00+08:00")
    end

    it "both return Z when time is UTC" do
      t = Time.utc(2023, 6, 15, 9, 0, 0)
      data = {
        run_id: "test_2",
        name: nil,
        distance: nil,
        moving_time: nil,
        elapsed_time: nil,
        sport_category: "run",
        sport_type: nil,
        start_date: t,
        start_date_local: t,
        location_country: nil,
        summary_polyline: nil,
        average_heartrate: nil,
        elevation_gain: nil,
        source: "test"
      }
      attrs = parser.send(:build_activity_attrs, data)
      expect(attrs[:start_date]).to eq("2023-06-15T09:00:00Z")
      expect(attrs[:start_date_local]).to eq("2023-06-15T09:00:00Z")
    end
  end
end

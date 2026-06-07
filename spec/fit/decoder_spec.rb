RSpec.describe Workouts::FIT::Decoder do
  let(:fit_path) { File.expand_path("../fixtures/igpsport/fit_sample.50279925.fit", __dir__) }

  describe ".decode" do
    subject(:points) { described_class.decode(fit_path) }

    it "returns an array of GPS points" do
      expect(points).to be_an(Array)
      expect(points.size).to be > 0
    end

    it "each point is a hash with positionLat and positionLong" do
      points.each do |pt|
        expect(pt).to be_a(Hash)
        expect(pt).to have_key("positionLat")
        expect(pt).to have_key("positionLong")
      end
    end

    it "latitudes are in valid range" do
      points.each { |pt| expect(pt["positionLat"]).to be_between(-90, 90) }
    end

    it "longitudes are in valid range" do
      points.each { |pt| expect(pt["positionLong"]).to be_between(-180, 180) }
    end

    it "preserves SDK fields like timestamp and altitude" do
      expect(points.first).to have_key("timestamp")
      expect(points.first).to have_key("altitude")
    end

    it "preserves optional fields like cadence and temperature" do
      has_cadence = points.first.key?("cadence")
      has_temp = points.first.key?("temperature")
      expect(has_cadence || has_temp).to be true
    end

    it "filters out records without position" do
      has_all_positions = points.all? { |pt| pt["positionLat"] != nil && pt["positionLong"] != nil }
      expect(has_all_positions).to be true
    end

    it "converts semicircles to correct geographic coordinates" do
      lats = points.map { |pt| pt["positionLat"] }
      lngs = points.map { |pt| pt["positionLong"] }
      expect(lats.min).to be > 15
      expect(lngs.min).to be > 70
      expect(lats.max).to be < 55
      expect(lngs.max).to be < 140
    end
  end

  describe ".info" do
    subject(:info) { described_class.info(fit_path) }

    it "returns message type counts" do
      expect(info).to include("recordMesgs")
      expect(info["recordMesgs"]).to be > 0
    end
  end
end

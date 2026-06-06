RSpec.describe Workouts::FIT::Decoder do
  let(:fit_path) { File.expand_path("../fixtures/igpsport/fit_sample.50279925.fit", __dir__) }

  describe ".decode" do
    subject(:points) { described_class.decode(fit_path) }

    it "returns an array of GPS points" do
      expect(points).to be_an(Array)
      expect(points.size).to be > 0
    end

    it "each point has lat, lng, alt, timestamp, hr" do
      points.each do |pt|
        expect(pt.size).to eq(5)
        expect(pt[0]).to be_a(Float)
        expect(pt[1]).to be_a(Float)
      end
    end

    it "latitudes are in valid range" do
      points.each { |pt| expect(pt[0]).to be_between(-90, 90) }
    end

    it "longitudes are in valid range" do
      points.each { |pt| expect(pt[1]).to be_between(-180, 180) }
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

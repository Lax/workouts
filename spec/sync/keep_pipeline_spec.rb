RSpec.describe "Keep decryption pipeline" do
  let(:keep) { Workouts::Sync::Keep.new(config: {}, db: nil) }
  let(:fixtures) { File.expand_path("../fixtures/keep", __dir__) }

  describe "#decode_geo_points" do
    subject(:points) { keep.send(:decode_geo_points, encrypted_geo) }
    let(:encrypted_geo) { File.read(File.join(fixtures, "encrypted_geo.txt")) }

    it "returns an array" do
      expect(points).to be_an(Array)
    end

    it "returns the expected number of points" do
      plain = JSON.parse(File.read(File.join(fixtures, "geo_plain.json")))
      expect(points.size).to eq(plain.size)
    end

    it "each point has latitude, longitude, and timestamp" do
      points.each do |pt|
        expect(pt).to include("latitude", "longitude", "timestamp")
      end
    end

    it "latitudes are in valid range" do
      points.each do |pt|
        expect(pt["latitude"]).to be_between(-90, 90)
      end
    end

    it "longitudes are in valid range" do
      points.each do |pt|
        expect(pt["longitude"]).to be_between(-180, 180)
      end
    end

    it "produces the same output as the original plaintext" do
      plain = JSON.parse(File.read(File.join(fixtures, "geo_plain.json")))
      expect(points).to eq(plain)
    end

    context "when geo data is nil" do
      it "returns nil" do
        expect(keep.send(:decode_geo_points, nil)).to be_nil
      end
    end

    context "when geo data is malformed" do
      it "returns nil" do
        expect(keep.send(:decode_geo_points, "not-valid-base64!!")).to be_nil
      end
    end
  end

  describe "#decode_hr_data" do
    subject(:hr) { keep.send(:decode_hr_data, encrypted_hr) }
    let(:encrypted_hr) { File.read(File.join(fixtures, "encrypted_hr.txt")) }

    context "when fixture has HR data" do
      let(:encrypted_hr) { Base64.strict_encode64(Zlib::Deflate.deflate('[{"timestamp":100,"beatsPerMinute":140}]')) }

      it "returns an array" do
        expect(hr).to be_an(Array)
      end

      it "parses HR entries" do
        expect(hr.first).to include("timestamp", "beatsPerMinute")
      end
    end

    context "when HR data is empty" do
      let(:encrypted_hr) { "" }

      it "returns nil" do
        expect(hr).to be_nil
      end
    end

    context "when HR data is nil" do
      let(:encrypted_hr) { nil }

      it "returns nil" do
        expect(hr).to be_nil
      end
    end
  end

  describe "#compute_wgs_points" do
    subject(:wgs) do
      keep.send(:compute_wgs_points, payload, run_data)
    end

    let(:run_data) { JSON.parse(File.read(File.join(fixtures, "run_data.json"))) }
    let(:geo_points) { JSON.parse(File.read(File.join(fixtures, "geo_plain.json"))) }

    let(:payload) do
      { geo_points: geo_points, hr_data: nil }
    end

    it "returns an array" do
      expect(wgs).to be_an(Array)
    end

    it "returns the same number of points as input" do
      expect(wgs.size).to eq(geo_points.size)
    end

    it "each point has lat, lng, alt, time, hr" do
      wgs.each do |pt|
        expect(pt.size).to eq(5)
        expect(pt[0]).to be_a(Float)  # lat
        expect(pt[1]).to be_a(Float)  # lng
      end
    end

    it "latitudes are within China range (GCJ-02 input → WGS84 output)" do
      wgs.each do |pt|
        expect(pt[0]).to be_between(10, 55)
      end
    end

    it "longitudes are within China range" do
      wgs.each do |pt|
        expect(pt[1]).to be_between(70, 140)
      end
    end

    context "with no geo points" do
      let(:geo_points) { [] }
      it { is_expected.to eq([]) }
    end

    context "with nil geo points" do
      let(:geo_points) { nil }
      it { is_expected.to eq([]) }
    end
  end

  describe "#build_activity_from_wgs" do
    subject(:activity) do
      keep.send(:build_activity_from_wgs, run_data, wgs_points)
    end

    let(:run_data) { JSON.parse(File.read(File.join(fixtures, "run_data.json"))) }
    let(:geo_points) { JSON.parse(File.read(File.join(fixtures, "geo_plain.json"))) }
    let(:wgs_points) do
      payload = { geo_points: geo_points, hr_data: nil }
      keep.send(:compute_wgs_points, payload, run_data)
    end

    it "returns a hash" do
      expect(activity).to be_a(Hash)
    end

    it "has a run_id starting with keep_" do
      expect(activity[:run_id]).to match(/\Akeep_\d+\z/)
    end

    it "sets sport_category to run" do
      expect(activity[:sport_category]).to eq("run")
    end

    it "has a positive distance" do
      expect(activity[:distance]).to be > 0
    end

    it "has a valid summary_polyline" do
      expect(activity[:summary_polyline]).to be_a(String)
      expect(activity[:summary_polyline].length).to be > 0
    end

    it "has moving_time matching duration" do
      expect(activity[:moving_time]).to eq(run_data["duration"])
    end

    it "has source set to keep" do
      expect(activity[:source]).to eq("keep")
    end

    context "with no wgs points" do
      let(:wgs_points) { [] }
      it "still builds activity without polyline" do
        expect(activity[:run_id]).to match(/\Akeep_\d+\z/)
        expect(activity[:summary_polyline]).to be_nil
      end
    end
  end
end

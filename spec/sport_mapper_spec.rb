RSpec.describe Workouts::SportMapper do
  describe "#canonicalize" do
    it "maps exact aliases" do
      expect(described_class.canonicalize("running")).to eq("run")
      expect(described_class.canonicalize("cycling")).to eq("ride")
      expect(described_class.canonicalize("strengthtraining")).to eq("workout")
    end

    it "maps extended aliases (trail, virtual, indoor, gravel, ebike, backcountry, nordic)" do
      expect(described_class.canonicalize("trailrun")).to eq("run")
      expect(described_class.canonicalize("virtualrun")).to eq("run")
      expect(described_class.canonicalize("indoorrun")).to eq("run")
      expect(described_class.canonicalize("mountainbike")).to eq("ride")
      expect(described_class.canonicalize("gravelride")).to eq("ride")
      expect(described_class.canonicalize("ebikeride")).to eq("ride")
      expect(described_class.canonicalize("backcountryski")).to eq("ski")
      expect(described_class.canonicalize("nordicski")).to eq("ski")
    end

    it "maps via keyword matching" do
      expect(described_class.canonicalize("mountaineering")).to eq("hike")
      expect(described_class.canonicalize("jogging")).to eq("run")
      expect(described_class.canonicalize("elliptical")).to eq("workout")
      expect(described_class.canonicalize("crossfit")).to eq("workout")
      expect(described_class.canonicalize("snowboard")).to eq("ski")
    end

    it "maps via Levenshtein distance" do
      expect(described_class.canonicalize("swiming")).to eq("swim")
      expect(described_class.canonicalize("runing")).to eq("run")
    end

    it "returns other for unrecognized input" do
      expect(described_class.canonicalize("skateboarding")).to eq("other")
    end

    it "returns other for nil" do
      expect(described_class.canonicalize(nil)).to eq("other")
    end

    it "returns other for empty string" do
      expect(described_class.canonicalize("")).to eq("other")
    end
  end
end

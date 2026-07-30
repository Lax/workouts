RSpec.describe Workouts::Timezone::Resolver do
  subject(:resolver) { described_class.new(config) }

  let(:config) { {"system" => {"timezone" => "Asia/Shanghai"}} }

  describe "#resolve" do
    context "with valid GPS coordinates on land" do
      # Shanghai coordinates → "Asia/Shanghai"
      it "returns the correct timezone for Shanghai" do
        expect(resolver.resolve(31.23, 121.47)).to eq("Asia/Shanghai")
      end

      # New York coordinates → "America/New_York"
      it "returns the correct timezone for New York" do
        expect(resolver.resolve(40.71, -74.01)).to eq("America/New_York")
      end

      # London coordinates → "Europe/London"
      it "returns the correct timezone for London" do
        tz = resolver.resolve(51.51, -0.13)
        expect(tz).to eq("Europe/London")
      end
    end

    context "with ocean coordinates (timezone_finder returns nil)" do
      it "falls back to config default timezone" do
        expect(resolver.resolve(0, 0)).to eq("Asia/Shanghai")
      end
    end

    context "with nil coordinates" do
      it "returns default when lat is nil" do
        expect(resolver.resolve(nil, 121.47)).to eq("Asia/Shanghai")
      end

      it "returns default when lng is nil" do
        expect(resolver.resolve(31.23, nil)).to eq("Asia/Shanghai")
      end

      it "returns default when both are nil" do
        expect(resolver.resolve(nil, nil)).to eq("Asia/Shanghai")
      end
    end

    context "with custom default" do
      let(:config) { {"system" => {"timezone" => "America/Chicago"}} }

      it "uses the configured default" do
        expect(resolver.resolve(nil, nil)).to eq("America/Chicago")
      end
    end

    context "when config has no timezone key" do
      let(:config) { {"system" => {}} }

      it "falls back to Asia/Shanghai" do
        expect(resolver.resolve(nil, nil)).to eq("Asia/Shanghai")
      end
    end

    context "when config is empty" do
      let(:config) { {} }

      it "falls back to Asia/Shanghai" do
        expect(resolver.resolve(nil, nil)).to eq("Asia/Shanghai")
      end
    end

    context "with stub TimezoneFinder (injected finder)" do
      let(:mock_finder) do
        double("TimezoneFinder", timezone_at: "Europe/Berlin")
      end
      subject(:resolver) { described_class.new(config, finder: mock_finder) }

      it "uses the injected finder instead of creating a real one" do
        expect(resolver.resolve(52.52, 13.40)).to eq("Europe/Berlin")
      end

      it "falls back to default when finder returns nil" do
        allow(mock_finder).to receive(:timezone_at).and_return(nil)
        expect(resolver.resolve(52.52, 13.40)).to eq("Asia/Shanghai")
      end

      it "falls back when finder returns empty string" do
        allow(mock_finder).to receive(:timezone_at).and_return("")
        expect(resolver.resolve(52.52, 13.40)).to eq("Asia/Shanghai")
      end
    end
  end
end

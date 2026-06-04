RSpec.describe Workouts::Geo::Polyline do
  let(:points) do
    [
      [40.7128, -74.0060],
      [40.7130, -74.0058],
      [40.7132, -74.0055]
    ]
  end

  it "encodes points to polyline string" do
    encoded = described_class.encode(points)
    expect(encoded).to be_a(String)
    expect(encoded).not_to be_empty
  end

  it "decodes polyline string back to points" do
    encoded = described_class.encode(points)
    decoded = described_class.decode(encoded)
    expect(decoded.length).to eq(points.length)
    expect(decoded[0][0]).to be_within(1e-5).of(points[0][0])
    expect(decoded[0][1]).to be_within(1e-5).of(points[0][1])
  end

  it "round-trips perfectly" do
    test_points = [
      [38.5, -120.2],
      [40.7, -74.0],
      [39.9, 116.4],
      [-33.8, 151.2],
      [48.8, 2.3]
    ]
    encoded = described_class.encode(test_points)
    decoded = described_class.decode(encoded)
    test_points.each_with_index do |(lat, lng), i|
      expect(decoded[i][0]).to be_within(1e-5).of(lat)
      expect(decoded[i][1]).to be_within(1e-5).of(lng)
    end
  end

  it "returns nil for nil input on decode" do
    expect(described_class.decode(nil)).to be_nil
  end

  it "returns nil for empty string on decode" do
    expect(described_class.decode("")).to be_nil
  end

  it "produces valid polyline" do
    encoded = described_class.encode([[40.7128, -74.0060]])
    expect(encoded).to be_a(String)
    expect(encoded.length).to be > 0
    decoded = described_class.decode(encoded)
    expect(decoded[0][0]).to be_within(1e-5).of(40.7128)
    expect(decoded[0][1]).to be_within(1e-5).of(-74.0060)
  end

  it "handles single point" do
    encoded = described_class.encode([[40.7128, -74.0060]])
    decoded = described_class.decode(encoded)
    expect(decoded.length).to eq(1)
    expect(decoded[0][0]).to be_within(1e-5).of(40.7128)
  end
end

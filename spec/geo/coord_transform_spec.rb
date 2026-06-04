RSpec.describe Workouts::Geo::CoordTransform do
  it "converts WGS84 to GCJ-02 for Beijing" do
    lat, lng = described_class.wgs84_to_gcj02(39.9087, 116.3975)
    expect(lat).to be_within(0.01).of(39.910)
    expect(lng).to be_within(0.01).of(116.404)
  end

  it "round-trips WGS84→GCJ-02→WGS84 exactly" do
    wgs = [39.9087, 116.3975]
    gcj = described_class.wgs84_to_gcj02(wgs[0], wgs[1])
    back = described_class.gcj02_to_wgs84_exact(gcj[0], gcj[1])
    expect(back[0]).to be_within(1e-10).of(wgs[0])
    expect(back[1]).to be_within(1e-10).of(wgs[1])
  end

  it "round-trips for Shanghai" do
    wgs = [31.2304, 121.4737]
    gcj = described_class.wgs84_to_gcj02(wgs[0], wgs[1])
    back = described_class.gcj02_to_wgs84_exact(gcj[0], gcj[1])
    expect(back[0]).to be_within(1e-10).of(wgs[0])
    expect(back[1]).to be_within(1e-10).of(wgs[1])
  end

  it "returns identity for coordinates outside China" do
    sf = [37.7749, -122.4194]
    result = described_class.wgs84_to_gcj02(sf[0], sf[1])
    expect(result).to eq(sf)
  end

  it "converts between GCJ-02 and BD-09" do
    gcj = [39.9101, 116.4037]
    bd = described_class.gcj02_to_bd09(gcj[0], gcj[1])
    back = described_class.bd09_to_gcj02(bd[0], bd[1])
    expect(back[0]).to be_within(1e-5).of(gcj[0])
    expect(back[1]).to be_within(1e-5).of(gcj[1])
  end

  it "round-trips WGS84→BD-09→WGS84" do
    wgs = [39.9087, 116.3975]
    bd = described_class.wgs84_to_bd09(wgs[0], wgs[1])
    back = described_class.bd09_to_wgs84(bd[0], bd[1])
    expect(back[0]).to be_within(1e-5).of(wgs[0])
    expect(back[1]).to be_within(1e-5).of(wgs[1])
  end

  it "detects out of China" do
    expect(described_class.out_of_china(-122.4, 37.8)).to be true
    expect(described_class.out_of_china(116.4, 39.9)).to be false
    expect(described_class.out_of_china(70.0, 35.0)).to be true
    expect(described_class.out_of_china(140.0, 35.0)).to be true
  end
end

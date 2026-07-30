RSpec.describe Workouts::Privacy::PolylineFilter do
  let(:points) do
    [
      [40.7128, -74.0060],
      [40.7129, -74.0059],
      [40.7130, -74.0058],
      [40.7131, -74.0057],
      [40.7132, -74.0055],
      [40.7133, -74.0054],
      [40.7134, -74.0053],
      [40.7135, -74.0052],
      [40.7136, -74.0051],
      [40.7137, -74.0050]
    ]
  end

  let(:polyline) { Workouts::Geo::Polyline.encode(points) }

  it "removes start and end points within range" do
    filter = described_class.new(config: {"start_end_range" => 50})
    result = filter.filter(polyline)
    expect(result).not_to be_nil

    decoded = Workouts::Geo::Polyline.decode(result)
    expect(decoded.length).to be < points.length
  end

  it "returns nil for nil input" do
    filter = described_class.new
    expect(filter.filter(nil)).to be_nil
  end

  it "returns nil for empty input" do
    filter = described_class.new
    expect(filter.filter("")).to be_nil
  end

  it "does not filter when range is 0" do
    filter = described_class.new(config: {"start_end_range" => 0})
    expect(filter.filter(polyline)).to eq(polyline)
  end

  it "filters around a specific polyline" do
    ignore_point = Workouts::Geo::Polyline.encode([[40.7130, -74.0058]])
    filter = described_class.new(config: {
      "start_end_range" => 0,
      "polyline" => ignore_point,
      "range" => 30
    })
    result = filter.filter(polyline)
    expect(result).not_to be_nil

    decoded = Workouts::Geo::Polyline.decode(result)
    expect(decoded.length).to be < points.length
  end

  it "reports before_saving setting" do
    filter_normal = described_class.new
    expect(filter_normal.before_saving?).to be false

    filter_before = described_class.new(config: {"before_saving" => true})
    expect(filter_before.before_saving?).to be true
  end
end

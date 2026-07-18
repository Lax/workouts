RSpec.describe Workouts::Parser::FIT do
  let(:fit_path) { File.expand_path("../fixtures/igpsport/fit_sample.50279925.fit", __dir__) }

  subject { described_class.new }

  it "parses a FIT file into one activity" do
    result = subject.call(fit_path)
    expect(result.length).to eq(1)
    expect(result[0][:distance]).to be > 0
    expect(result[0][:sport_category]).to be_a(String)
    expect(result[0][:start_date]).not_to be_nil
  end

  it "generates a valid polyline" do
    result = subject.call(fit_path)
    expect(result[0][:summary_polyline]).not_to be_nil
    decoded = Workouts::Geo::Polyline.decode(result[0][:summary_polyline])
    expect(decoded.length).to be > 0
  end

  it "computes elevation gain" do
    result = subject.call(fit_path)
    expect(result[0][:elevation_gain]).to be_a(Numeric)
  end

  it "computes moving time" do
    result = subject.call(fit_path)
    expect(result[0][:moving_time]).to be > 0
    expect(result[0][:elapsed_time]).to be > 0
  end

  it "sets sport_category from the FIT session sport" do
    result = subject.call(fit_path)
    expect(%w[run ride hike walk swim ski workout other]).to include(result[0][:sport_category])
  end

  it "returns empty for file with no GPS points" do
    allow(Workouts::FIT::Decoder).to receive(:decode).and_return([])
    result = subject.call("/nonexistent/test.fit")
    expect(result).to eq([])
  end
end

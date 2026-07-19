# frozen_string_literal: true

RSpec.describe Workouts::Dedup::Service do
  subject(:service) { described_class.new(db) }
  let(:db) { instance_double("Sequel::Database") }
  let(:trajectory) { instance_double(Workouts::Dedup::Trajectory) }

  before do
    allow(Workouts::Dedup::Trajectory).to receive(:new).and_return(trajectory)
  end

  describe "#classify_flag" do
    let(:a) { { run_id: "garmin_1" } }
    let(:b) { { run_id: "strava_2" } }

    it "returns derived for score >= 0.85" do
      expect(service.send(:classify_flag, a, b, 0.85)).to eq("derived")
    end

    it "returns duplicate for equivalent containment" do
      allow(trajectory).to receive(:points).with("garmin_1").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:points).with("strava_2").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:containment_relation).and_return(:equivalent)
      expect(service.send(:classify_flag, a, b, 0.5)).to eq("duplicate")
    end

    it "returns contained for contained_a containment" do
      allow(trajectory).to receive(:points).with("garmin_1").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:points).with("strava_2").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:containment_relation).and_return(:contained_a)
      expect(service.send(:classify_flag, a, b, 0.5)).to eq("contained")
    end

    it "returns partial for partial containment" do
      allow(trajectory).to receive(:points).with("garmin_1").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:points).with("strava_2").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:containment_relation).and_return(:partial)
      expect(service.send(:classify_flag, a, b, 0.5)).to eq("partial")
    end

    it "returns cross for cross containment" do
      allow(trajectory).to receive(:points).with("garmin_1").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:points).with("strava_2").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }] * 5)
      allow(trajectory).to receive(:containment_relation).and_return(:cross)
      expect(service.send(:classify_flag, a, b, 0.5)).to eq("cross")
    end

    it "returns similar when L2 files missing" do
      allow(trajectory).to receive(:points).with("garmin_1").and_return(nil)
      allow(trajectory).to receive(:points).with("strava_2").and_return(nil)
      expect(service.send(:classify_flag, a, b, 0.5)).to eq("similar")
    end

    it "returns similar when points have < 2 points" do
      allow(trajectory).to receive(:points).with("garmin_1").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }])
      allow(trajectory).to receive(:points).with("strava_2").and_return([{ "latitude" => 39.0, "longitude" => 116.0 }])
      expect(service.send(:classify_flag, a, b, 0.5)).to eq("similar")
    end

    it "returns nil for score < 0.15" do
      expect(service.send(:classify_flag, a, b, 0.14)).to be_nil
    end
  end
end

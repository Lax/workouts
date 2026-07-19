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

  describe "#run" do
    context "incremental mode" do
      it "skips already-grouped records" do
        acts = double("activities_dataset")
        allow(db).to receive(:[]).with(:activities).and_return(acts)
        allow(acts).to receive(:where).and_return(acts)
        allow(acts).to receive(:order).with(:start_date).and_return(acts)
        allow(acts).to receive(:size).and_return(0)

        svc = described_class.new(db, incremental: true)
        expect(svc.run).to eq(0)
      end
    end

    context "group writing" do
      let(:activities) do
        base = Time.now.utc
        [
          { run_id: "garmin_1", source: "garmin", start_date: base.iso8601,
            distance: 5000, elapsed_time: 1800, moving_time: 1700,
            sport_category: "run", sport_type: "road_running" },
          { run_id: "strava_2", source: "strava", start_date: (base + 60).iso8601,
            distance: 5100, elapsed_time: 1750, moving_time: 1680,
            sport_category: "run", sport_type: "run" }
        ]
      end

      it "writes dedup_groups when matches found" do
        allow(trajectory).to receive(:points).and_return(
          [{ "latitude" => 39.0, "longitude" => 116.0 }] * 5,
          [{ "latitude" => 39.0, "longitude" => 116.0 }] * 5
        )
        allow(trajectory).to receive(:containment_relation).and_return(:equivalent)

        acts = double("activities_dataset")
        allow(db).to receive(:[]).with(:activities).and_return(acts)
        allow(acts).to receive(:where).and_return(acts)
        allow(acts).to receive(:order).with(:start_date).and_return(activities)
        allow(acts).to receive(:get).and_return(nil)
        allow(acts).to receive(:update).and_return(1)
        allow(acts).to receive(:all).and_return(activities)

        dedup_groups = double("dedup_groups_dataset")
        allow(db).to receive(:[]).with(:dedup_groups).and_return(dedup_groups)
        allow(dedup_groups).to receive(:insert_conflict).and_return(dedup_groups)
        allow(dedup_groups).to receive(:insert).and_return(1)

        dedup_members = double("dedup_members_dataset")
        allow(db).to receive(:[]).with(:dedup_group_members).and_return(dedup_members)
        allow(dedup_members).to receive(:insert_conflict).and_return(dedup_members)
        allow(dedup_members).to receive(:insert).and_return(1)

        svc = described_class.new(db)
        count = svc.run
        expect(count).to be > 0
      end
    end
  end
end

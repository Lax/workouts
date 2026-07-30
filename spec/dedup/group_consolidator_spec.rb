# frozen_string_literal: true

RSpec.describe Workouts::Dedup::GroupConsolidator do
  subject(:consolidator) { described_class.new }

  def pair(a_run_id, b_run_id)
    [{run_id: a_run_id}, {run_id: b_run_id}]
  end

  describe "#consolidate" do
    it "returns empty hash for no pairs" do
      expect(consolidator.consolidate([])).to eq({})
    end

    it "groups connected pairs into one group" do
      pairs = [
        {a: {run_id: "a"}, b: {run_id: "b"}},
        {a: {run_id: "b"}, b: {run_id: "c"}}
      ]
      result = consolidator.consolidate(pairs)
      expect(result.size).to eq(1)
      group = result.values.first
      expect(group).to contain_exactly("a", "b", "c")
    end

    it "creates separate groups for disjoint pairs" do
      pairs = [
        {a: {run_id: "a"}, b: {run_id: "b"}},
        {a: {run_id: "c"}, b: {run_id: "d"}}
      ]
      result = consolidator.consolidate(pairs)
      expect(result.size).to eq(2)
    end

    it "handles single pair" do
      pairs = [
        {a: {run_id: "garmin_1"}, b: {run_id: "strava_2"}}
      ]
      result = consolidator.consolidate(pairs)
      expect(result.size).to eq(1)
      expect(result.values.first).to contain_exactly("garmin_1", "strava_2")
    end

    it "generates deterministic group_id from member ids" do
      pairs = [
        {a: {run_id: "x"}, b: {run_id: "y"}}
      ]
      first = consolidator.consolidate(pairs)
      second = consolidator.consolidate(pairs)
      expect(first.keys.first).to eq(second.keys.first)
    end
  end
end

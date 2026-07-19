# frozen_string_literal: true

RSpec.describe Workouts::Dedup::Matcher do
  describe ".external_id_match" do
    it "returns hash with confidence 1.0 for matching UUIDs" do
      a = { external_id: "544EA64D-4645-4BBC-9147-638B642FCFE1" }
      b = { external_id: "544EA64D-4645-4BBC-9147-638B642FCFE1" }
      result = described_class.external_id_match(a, b)
      expect(result).to eq({ confidence: 1.0, flag: "derived", source: "external_id" })
    end

    it "handles strava://activities/ prefix normalization" do
      a = { external_id: "strava://activities/3056096737" }
      b = { external_id: "3056096737" }
      result = described_class.external_id_match(a, b)
      expect(result).to eq({ confidence: 1.0, flag: "derived", source: "external_id" })
    end

    it "returns nil for different UUIDs" do
      a = { external_id: "abc" }
      b = { external_id: "xyz" }
      expect(described_class.external_id_match(a, b)).to be_nil
    end

    it "returns nil when either side is nil" do
      expect(described_class.external_id_match({ external_id: nil }, { external_id: "abc" })).to be_nil
      expect(described_class.external_id_match({ external_id: "abc" }, { external_id: nil })).to be_nil
    end

    it "returns nil when either side is empty string" do
      expect(described_class.external_id_match({ external_id: "" }, { external_id: "abc" })).to be_nil
    end
  end

  describe ".match" do
    it "returns 1.0 for external_id match, bypassing time heuristic" do
      a = { external_id: "same", start_date: "2023-01-01T00:00:00Z", sport_category: "run" }
      b = { external_id: "same", start_date: "2023-01-02T00:00:00Z", sport_category: "ride" }
      expect(described_class.match(a, b)).to eq(1.0)
    end

    it "falls through to heuristic when external_id differs" do
      a = { external_id: "a", start_date: "2023-01-01T00:00:00Z", elapsed_time: 3600, distance: 10000, sport_category: "run" }
      b = { external_id: "b", start_date: "2023-01-01T00:01:00Z", elapsed_time: 3600, distance: 10000, sport_category: "run" }
      score = described_class.match(a, b)
      expect(score).to be > 0.8
      expect(score).to be < 1.0
    end

    it "returns 0.0 when no external_id and time diff too large" do
      a = { external_id: nil, start_date: "2023-01-01T00:00:00Z", elapsed_time: 3600, distance: 10000, sport_category: "run" }
      b = { external_id: nil, start_date: "2023-01-02T00:00:00Z", elapsed_time: 3600, distance: 10000, sport_category: "run" }
      expect(described_class.match(a, b)).to eq(0.0)
    end
  end

  describe ".trajectory_score" do
    it "returns weighted sum of provided scores" do
      scores = { dtw_similarity: 1.0, overlap_score: 1.0, hausdorff_score: 1.0, distance_match: 1.0 }
      expect(described_class.trajectory_score(scores)).to eq(1.0)
    end

    it "returns 0.0 for empty scores hash" do
      expect(described_class.trajectory_score({})).to eq(0.0)
    end

    it "returns 0.0 for nil" do
      expect(described_class.trajectory_score(nil)).to eq(0.0)
    end

    it "ignores invalid scores (non-numeric)" do
      scores = { dtw_similarity: "bad", overlap_score: 1.0, hausdorff_score: 1.0, distance_match: 1.0 }
      result = described_class.trajectory_score(scores)
      expected = 0.0 * 0.30 + 1.0 * 0.25 + 1.0 * 0.25 + 1.0 * 0.20
      expect(result).to eq(expected.round(4))
    end

    it "clamps out-of-range scores to 0.0 contribution" do
      scores = { dtw_similarity: 2.0, overlap_score: 1.0, hausdorff_score: 1.0, distance_match: 1.0 }
      result = described_class.trajectory_score(scores)
      expected = 0.0 * 0.30 + 1.0 * 0.25 + 1.0 * 0.25 + 1.0 * 0.20
      expect(result).to eq(expected.round(4))
    end
  end
end

# frozen_string_literal: true

RSpec.describe Workouts::Dedup::Trajectory do
  subject(:trajectory) { described_class.new(nil) }

  let(:linear_track) do
    (0...10).map { |i| { "latitude" => 39.0 + i * 0.001, "longitude" => 116.0 } }
  end

  let(:identical_track) do
    (0...10).map { |i| { "latitude" => 39.0 + i * 0.001, "longitude" => 116.0 } }
  end

  let(:offset_track) do
    (0...10).map { |i| { "latitude" => 39.0 + i * 0.001 + 0.01, "longitude" => 116.0 + 0.01 } }
  end

  describe "#point_coordinates" do
    it "extracts from latitude/longitude keys" do
      pt = { "latitude" => 39.5, "longitude" => 116.3 }
      expect(trajectory.send(:point_coordinates, pt)).to eq([39.5, 116.3])
    end

    it "extracts from positionLat/positionLong keys" do
      pt = { "positionLat" => 39.5, "positionLong" => 116.3 }
      expect(trajectory.send(:point_coordinates, pt)).to eq([39.5, 116.3])
    end

    it "extracts symbol keys" do
      pt = { latitude: 39.5, longitude: 116.3 }
      expect(trajectory.send(:point_coordinates, pt)).to eq([39.5, 116.3])
    end

    it "returns nil for missing keys" do
      pt = { "altitude" => 100 }
      expect(trajectory.send(:point_coordinates, pt)).to be_nil
    end
  end

  describe "#perpendicular_distance" do
    it "returns 0 for point on the line" do
      a = [0.0, 0.0]
      b = [0.0, 0.01]
      pt = [0.0, 0.005]
      dist = trajectory.send(:perpendicular_distance, pt, a, b)
      expect(dist).to be < 1.0
    end

    it "returns positive for point off the line" do
      a = [0.0, 0.0]
      b = [0.0, 0.01]
      pt = [0.005, 0.005]
      dist = trajectory.send(:perpendicular_distance, pt, a, b)
      expect(dist).to be > 500.0
    end
  end

  describe "#min_distance_to_set" do
    it "returns 0 when pt matches a candidate" do
      candidates = [[39.0, 116.0], [39.001, 116.0]]
      dist = trajectory.send(:min_distance_to_set, [39.0, 116.0], candidates)
      expect(dist).to eq(0.0)
    end

    it "returns positive when pt is offset from all candidates" do
      candidates = [[39.0, 116.0], [39.001, 116.0]]
      dist = trajectory.send(:min_distance_to_set, [39.1, 116.0], candidates)
      expect(dist).to be > 10000.0
    end
  end

  describe "#douglas_peucker" do
    it "returns input for 2 or fewer points" do
      pts = [{ "latitude" => 39.0, "longitude" => 116.0 }]
      expect(trajectory.douglas_peucker(pts)).to eq(pts)
    end

    it "reduces collinear points to 2 (start+end)" do
      pts = (0...100).map { |i| { "latitude" => 39.0 + i * 0.00001, "longitude" => 116.0 } }
      result = trajectory.douglas_peucker(pts)
      expect(result.size).to eq(2)
      expect(result.first).to eq([39.0, 116.0])
      expect(result.last).to eq([39.0 + 99 * 0.00001, 116.0])
    end

    it "preserves non-collinear point" do
      pts = [
        { "latitude" => 39.0, "longitude" => 116.0 },
        { "latitude" => 39.005, "longitude" => 116.01 },
        { "latitude" => 39.01, "longitude" => 116.0 }
      ]
      result = trajectory.douglas_peucker(pts)
      expect(result.size).to eq(3)
    end
  end

  describe "#dtw_similarity" do
    it "returns 1.0 for identical tracks" do
      expect(trajectory.dtw_similarity(linear_track, identical_track)).to eq(1.0)
    end

    it "returns near-0 for very different tracks" do
      far_track = (0...10).map { |i| { "latitude" => 50.0 + i * 0.001, "longitude" => 120.0 } }
      score = trajectory.dtw_similarity(linear_track, far_track)
      expect(score).to be < 0.5
    end

    it "returns nil for < 2 points" do
      single = [{ "latitude" => 39.0, "longitude" => 116.0 }]
      expect(trajectory.dtw_similarity(single, linear_track)).to be_nil
    end

    it "returns nil for nil input" do
      expect(trajectory.dtw_similarity(nil, linear_track)).to be_nil
    end
  end

  describe "#hausdorff_distance" do
    it "returns 0 for identical tracks" do
      expect(trajectory.hausdorff_distance(linear_track, identical_track)).to eq(0.0)
    end

    it "returns positive for offset tracks" do
      dist = trajectory.hausdorff_distance(linear_track, offset_track)
      expect(dist).to be > 1000.0
    end
  end

  describe "#normalized_hausdorff_score" do
    it "returns 1.0 for identical tracks" do
      expect(trajectory.normalized_hausdorff_score(linear_track, identical_track)).to eq(1.0)
    end

    it "returns 0.0 for 2000m+ tracks" do
      very_far = (0...10).map { |i| { "latitude" => 50.0, "longitude" => 120.0 + i * 0.001 } }
      expect(trajectory.normalized_hausdorff_score(linear_track, very_far)).to eq(0.0)
    end
  end

  describe "#overlap_score" do
    it "returns 1.0 for identical tracks" do
      expect(trajectory.overlap_score(linear_track, identical_track)).to eq(1.0)
    end

    it "returns 0.0 for disjoint tracks" do
      disjoint = (0...10).map { |i| { "latitude" => 50.0 + i * 0.001, "longitude" => 120.0 } }
      expect(trajectory.overlap_score(linear_track, disjoint)).to eq(0.0)
    end

    it "returns nil for < 2 points" do
      single = [{ "latitude" => 39.0, "longitude" => 116.0 }]
      expect(trajectory.overlap_score(single, linear_track)).to be_nil
    end
  end

  describe "#containment_relation" do
    it "returns :equivalent for identical tracks" do
      expect(trajectory.containment_relation(linear_track, identical_track)).to eq(:equivalent)
    end

    it "returns :contained_a when A is subset of B" do
      subset = (0...50).map { |i| { "latitude" => 39.0 + i * 0.0005, "longitude" => 116.0 } }
      superset = (0...100).map { |i| { "latitude" => 39.0 + i * 0.0005, "longitude" => 116.0 } }
      expect(trajectory.containment_relation(subset, superset)).to eq(:contained_a)
    end

    it "returns :disjoint for far apart tracks" do
      disjoint = (0...10).map { |i| { "latitude" => 50.0 + i * 0.001, "longitude" => 120.0 } }
      expect(trajectory.containment_relation(linear_track, disjoint)).to eq(:disjoint)
    end

    it "returns :cross for barely touching tracks" do
      far_start = (0...100).map { |i| { "latitude" => 50.0 + i * 0.001, "longitude" => 120.0 } }
      far_start[0] = { "latitude" => 39.0, "longitude" => 116.0 }
      long = (0...100).map { |i| { "latitude" => 39.0 + i * 0.0005, "longitude" => 116.0 } }
      expect(trajectory.containment_relation(far_start, long)).to eq(:cross)
    end

    it "returns nil when both have < 2 points" do
      single = [{ "latitude" => 39.0, "longitude" => 116.0 }]
      expect(trajectory.containment_relation(single, single)).to be_nil
    end
  end
end

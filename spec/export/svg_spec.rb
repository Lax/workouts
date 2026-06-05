RSpec.describe Workouts::Export::SVG::GithubDrawer do
  let(:colors) do
    { background: "#222", track: "#4DD2FF", text: "#FFF", special: "#FF0" }
  end
  let(:sd) { { special_distance: 10, special_distance2: 20 } }
  let(:poster) { Workouts::Export::SVG::Poster.new("Test", "Test", colors, sd) }
  let(:drawer) { described_class.new(poster) }

  def build_track(start_date, distance: 5000, run_id: "t1")
    Workouts::Export::SVG::Track.new(
      { run_id: run_id, distance: distance, start_date: start_date,
        sport_category: "run", moving_time: 600 },
      colors, sd
    )
  end

  describe "#group_by_date" do
    it "groups tracks by YYYY-MM-DD" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", run_id: "a"),
        build_track("2024-06-15T14:30:00Z", run_id: "b"),
        build_track("2024-06-16T08:00:00Z", run_id: "c"),
      ]
      result = drawer.send(:group_by_date)
      expect(result.keys).to all(match(/^\d{4}-\d{2}-\d{2}$/))
      expect(result["2024-06-15"].size).to eq(2)
      expect(result["2024-06-16"].size).to eq(1)
    end
  end

  describe "#compute_length_range" do
    it "returns max daily total in meters" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", distance: 5000),
        build_track("2024-06-15T14:00:00Z", distance: 3000),
        build_track("2024-06-16T08:00:00Z", distance: 2000),
      ]
      grouped = drawer.send(:group_by_date)
      range = drawer.send(:compute_length_range, grouped)
      expect(range).to eq(8000.0)
    end
  end

  describe "#draw" do
    it "includes non-default fills for days with activity" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", distance: 8000),
        build_track("2024-07-20T08:00:00Z", distance: 5000),
      ]
      poster.width = 200
      poster.height = 100
      output = drawer.draw([], [180, 60], [10, 30])
      expect(output).to include("2024-06-15")
      expect(output).to include("2024-07-20")
      fills = output.scan(/fill="(#[^"]+)"/).flatten
      expect(fills.any? { |c| c != "#444444" }).to be true
    end
  end
end

RSpec.describe Workouts::Export::SVG::GithubDrawer do
  let(:colors) do
    { background: "#222", track: "#4DD2FF", text: "#FFF", special: "#FF0" }
  end
  let(:sd) { { special_distance: 10, special_distance2: 20 } }
  let(:poster) { Workouts::Export::SVG::Poster.new("Test", "Test", colors, sd) }
  let(:drawer) { described_class.new(poster) }

  def build_track(start_date, distance: 5000, run_id: "t1", category: "run")
    Workouts::Export::SVG::Track.new(
      { run_id: run_id, distance: distance, start_date: start_date,
        sport_category: category, moving_time: 600 },
      colors, sd
    )
  end

  describe "#group_by_date_and_category" do
    it "groups tracks by YYYY-MM-DD then by category" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", run_id: "a", category: "run"),
        build_track("2024-06-15T14:30:00Z", run_id: "b", category: "run"),
        build_track("2024-06-15T08:00:00Z", run_id: "c", category: "walk"),
        build_track("2024-06-16T08:00:00Z", run_id: "d", category: "ride"),
      ]
      result = drawer.send(:group_by_date_and_category)
      expect(result.keys).to all(match(/^\d{4}-\d{2}-\d{2}$/))
      expect(result["2024-06-15"]["run"].size).to eq(2)
      expect(result["2024-06-15"]["walk"].size).to eq(1)
      expect(result["2024-06-16"]["ride"].size).to eq(1)
    end
  end

  describe "#dominant_category" do
    it "picks category with highest distance/REFERENCE ratio" do
      grouped = {
        "run"  => [build_track("2024-06-15T10:00:00Z", distance: 3000, category: "run")],
        "walk" => [build_track("2024-06-15T08:00:00Z", distance: 2000, category: "walk")],
      }
      cat, len = drawer.send(:dominant_category, grouped)
      # walk 2km / 5 = 0.4, run 3km / 10 = 0.3 → walk wins
      expect(cat).to eq("walk")
      expect(len).to eq(2000)
    end

    it "prefers ride over walk when ride is proportionally more significant" do
      grouped = {
        "ride" => [build_track("2024-06-15T10:00:00Z", distance: 15_000, category: "ride")],
        "walk" => [build_track("2024-06-15T08:00:00Z", distance: 3_000, category: "walk")],
      }
      cat, _len = drawer.send(:dominant_category, grouped)
      # ride 15km / 20 = 0.75, walk 3km / 5 = 0.6 → ride wins
      expect(cat).to eq("ride")
    end
  end

  describe "#compute_per_category_max" do
    it "returns max daily distance per category" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", distance: 5000, category: "run"),
        build_track("2024-06-15T14:00:00Z", distance: 3000, category: "run"),
        build_track("2024-06-16T08:00:00Z", distance: 2000, category: "run"),
        build_track("2024-06-15T08:00:00Z", distance: 4000, category: "walk"),
      ]
      grouped = drawer.send(:group_by_date_and_category)
      maxes = drawer.send(:compute_per_category_max, grouped)
      expect(maxes["run"]).to eq(8000.0)
      expect(maxes["walk"]).to eq(4000.0)
    end
  end

  describe "#draw" do
    it "includes CSS class per dominant category" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", distance: 8000, category: "run"),
      ]
      poster.width = 200
      poster.height = 100
      output = drawer.draw([], [180, 60], [10, 30])
      expect(output).to include('class="s-run"')
    end

    it "includes non-default fills for days with activity" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", distance: 8000, category: "run"),
        build_track("2024-07-20T08:00:00Z", distance: 5000, category: "walk"),
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

  describe "#build_day_title" do
    it "includes category, distance, and time for single track" do
      poster.tracks = [build_track("2024-06-15T10:00:00Z", distance: 4000, category: "walk", run_id: "a")]
      grouped = drawer.send(:group_by_date_and_category)
      title = drawer.send(:build_day_title, "2024-06-15", grouped["2024-06-15"])
      expect(title).to match(/walk/)
      expect(title).to match(/4\.0 km/)
      expect(title).to match(/10min/)
      expect(title).not_to include("\n")
    end

    it "uses newline separator for multiple tracks" do
      poster.tracks = [
        build_track("2024-06-15T10:00:00Z", distance: 5000, category: "ride", run_id: "a"),
        build_track("2024-06-15T14:00:00Z", distance: 3000, category: "walk", run_id: "b"),
      ]
      grouped = drawer.send(:group_by_date_and_category)
      title = drawer.send(:build_day_title, "2024-06-15", grouped["2024-06-15"])
      expect(title).to include("\n")
      expect(title).to include("ride")
      expect(title).to include("walk")
    end
  end

  describe "#format_time" do
    it "returns empty string for nil" do
      expect(drawer.send(:format_time, nil)).to eq("")
    end

    it "returns minutes-only format" do
      expect(drawer.send(:format_time, 1500)).to eq("25min")
    end

    it "returns hours and minutes format" do
      expect(drawer.send(:format_time, 5400)).to eq("1h 30min")
    end
  end
end

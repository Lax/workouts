require "spec_helper"
require_relative "../support/seed_db"
require "tmpdir"
require "json"

RSpec.describe "Export pipeline: seed DB → JSON/Stats → Svelte" do
  let(:db) { create_seed_db }

  around { |ex| Dir.mktmpdir { |dir| @tmpdir = dir; ex.run } }
  attr_reader :tmpdir

  describe "Export::JSON" do
    it "produces valid JSON consumable by Svelte app" do
      count = Workouts::Export::JSON.new(db: db, output: "#{tmpdir}/activities.json").call
      expect(count).to eq(4)

      data = JSON.parse(File.read("#{tmpdir}/activities.json"))
      expect(data).to be_an(Array)
      expect(data.size).to eq(4)

      act = data.find { |a| a["run_id"] == "garmin_1" }
      expect(act["name"]).to eq("Morning Run")
      expect(act["distance"]).to eq(5_000)
      expect(act["type"]).to eq("run")
      expect(act["start_date"]).to eq("2025-01-15T08:00:00Z")
      expect(act["source"]).to eq("garmin")

      # Svelte app uses moving_time as number for sort/comparison
      expect(act["moving_time"]).to be_a(Integer)
      expect(act["moving_time"]).to eq(1800)

      # Sensor fields present
      expect(act["average_heartrate"]).to eq(145)
      expect(act["max_heartrate"]).to eq(172)
      expect(act["average_cadence"]).to eq(82)
      expect(act["average_power"]).to be_nil
      expect(act["calories"]).to eq(350)
      expect(act["average_temperature"]).to eq(18)
      expect(act["elevation_gain"]).to eq(25)
    end

    it "sorts by start_date descending" do
      Workouts::Export::JSON.new(db: db, output: "#{tmpdir}/activities.json").call
      data = JSON.parse(File.read("#{tmpdir}/activities.json"))
      dates = data.map { |a| a["start_date"] }
      expect(dates).to eq(dates.sort.reverse)
    end

    it "filters by sport_category" do
      count = Workouts::Export::JSON.new(db: db, output: "#{tmpdir}/activities.json",
        activity_filter: "run").call
      expect(count).to eq(1)
      data = JSON.parse(File.read("#{tmpdir}/activities.json"))
      expect(data.all? { |a| a["type"] == "run" }).to be true
    end
  end

  describe "Export::Stats" do
    it "produces valid stats JSON consumable by Svelte app" do
      count = Workouts::Export::Stats.new(db: db, output: "#{tmpdir}/stats.json").call
      expect(count).to eq(4)

      stats = JSON.parse(File.read("#{tmpdir}/stats.json"))
      expect(stats).to have_key("summary")
      expect(stats).to have_key("monthly")
      expect(stats).to have_key("yearly")
      expect(stats).to have_key("streaks")
      expect(stats).to have_key("activity_types")

      s = stats["summary"]
      expect(s["total_activities"]).to eq(4)
      expect(s["total_distance_km"]).to be_within(0.01).of(40.0)
      expect(s["total_moving_time_h"]).to be_within(0.01).of(3.67)

      breakdown = s["sport_breakdown"]
      expect(breakdown.size).to eq(4)
      expect(breakdown.map { |b| b["category"] }).to contain_exactly("run", "ride", "walk", "hike")

      expect(stats["activity_types"]).to contain_exactly("run", "ride", "walk", "hike")
      expect(stats["streaks"]).to have_key("current")
      expect(stats["streaks"]).to have_key("all_time")
    end

    it "filters by sport_category" do
      count = Workouts::Export::Stats.new(db: db, output: "#{tmpdir}/stats.json",
        activity_filter: "run").call
      expect(count).to eq(1)
      stats = JSON.parse(File.read("#{tmpdir}/stats.json"))
      expect(stats["summary"]["total_activities"]).to eq(1)
      expect(stats["activity_types"]).to eq(["run"])
    end
  end

  describe "Pipeline integration" do
    it "seed → export → Svelte can parse both files" do
      Workouts::Export::JSON.new(db: db, output: "#{tmpdir}/activities.json").call
      Workouts::Export::Stats.new(db: db, output: "#{tmpdir}/stats.json").call

      activities = JSON.parse(File.read("#{tmpdir}/activities.json"))
      stats = JSON.parse(File.read("#{tmpdir}/stats.json"))

      expect(activities.size).to eq(4)
      expect(stats["summary"]["total_activities"]).to eq(4)

      # Verify Svelte-required fields exist
      required = %w[run_id name distance moving_time type start_date source]
      activities.each do |a|
        required.each { |f| expect(a).to have_key(f) }
      end

      # Compatible with Svelte sort/filter (numeric comparisons)
      expect(activities.map { |a| a["distance"] }).to all(be_a(Numeric))
      expect(activities.map { |a| a["moving_time"] }).to all(be_a(Numeric))
    end

    it "output files are non-empty valid JSON" do
      Workouts::Export::JSON.new(db: db, output: "#{tmpdir}/activities.json").call
      Workouts::Export::Stats.new(db: db, output: "#{tmpdir}/stats.json").call

      expect(File.size("#{tmpdir}/activities.json")).to be > 50
      expect(File.size("#{tmpdir}/stats.json")).to be > 100

      expect { JSON.parse(File.read("#{tmpdir}/activities.json")) }.not_to raise_error
      expect { JSON.parse(File.read("#{tmpdir}/stats.json")) }.not_to raise_error
    end
  end
end

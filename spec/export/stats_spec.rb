RSpec.describe Workouts::Export::Stats do
  let(:db) do
    d = Sequel.sqlite
    d.create_table(:activities) do
      Integer :id, primary_key: true
      String :run_id, null: false, unique: true
      String :name; Float :distance; Integer :moving_time; Integer :elapsed_time
      String :sport_category, null: false, default: "run"; String :sport_type
      String :start_date; String :start_date_local; String :location_country
      String :summary_polyline, text: true
      Float :average_heartrate; Float :max_heartrate
      Float :average_cadence; Float :max_cadence; Float :average_power; Float :max_power
      Integer :calories; Float :average_temperature
      Float :average_speed; Float :elevation_gain
      String :source
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
    d
  end

  let(:output) { File.join(Dir.mktmpdir, "stats.json") }
  subject(:stats_exporter) { described_class.new(db:, output:) }

  after { FileUtils.rm_rf(File.dirname(output)) }

  describe "#call" do
    context "with mixed activities" do
      before do
        now = Time.now.utc
        # 2024-06-15: run
        db[:activities].insert(
          run_id: "t1", name: "Run 1", distance: 5000, moving_time: 1500,
          sport_category: "run", start_date: "2024-06-15T01:00:00Z",
          source: "strava", created_at: now, updated_at: now,
          average_heartrate: 145
        )
        # 2024-06-16: run (same day, different activity)
        db[:activities].insert(
          run_id: "t2", name: "Run 2", distance: 8000, moving_time: 2400,
          sport_category: "run", start_date: "2024-06-16T01:00:00Z",
          source: "strava", created_at: now, updated_at: now,
          average_heartrate: 150
        )
        # 2024-07-01: ride
        db[:activities].insert(
          run_id: "t3", name: "Ride 1", distance: 30000, moving_time: 5400,
          sport_category: "ride", start_date: "2024-07-01T01:00:00Z",
          source: "garmin", created_at: now, updated_at: now,
          average_cadence: 85, average_power: 200,
          average_heartrate: 148
        )
      end

      it "returns total activity count" do
        expect(stats_exporter.call).to eq(3)
      end

      it "writes stats JSON file" do
        stats_exporter.call
        expect(File.exist?(output)).to be true
        data = JSON.parse(File.read(output))
        expect(data["summary"]["total_activities"]).to eq(3)
        expect(data["summary"]["total_distance_km"]).to be_within(0.1).of(43.0)
      end

      it "has all top-level keys" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        expect(data.keys).to contain_exactly("summary", "monthly", "yearly", "streaks", "activity_types")
      end

      it "summary has required fields" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        s = data["summary"]
        expect(s).to have_key("total_activities")
        expect(s).to have_key("total_distance_km")
        expect(s).to have_key("total_moving_time_h")
        expect(s).to have_key("total_elevation_gain_m")
        expect(s).to have_key("avg_cadence")
        expect(s).to have_key("avg_power")
        expect(s).to have_key("sport_breakdown")
      end

      it "sport_breakdown is sorted by count desc" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        counts = data["summary"]["sport_breakdown"].map { |b| b["count"] }
        expect(counts).to eq(counts.sort.reverse)
      end

      it "sport_breakdown has run and ride entries" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        cats = data["summary"]["sport_breakdown"].map { |b| b["category"] }
        expect(cats).to include("run", "ride")
      end

      it "monthly entries have year, month, count, distance_km" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        data["monthly"].each do |m|
          expect(m).to have_key("year")
          expect(m).to have_key("month")
          expect(m).to have_key("count")
          expect(m).to have_key("distance_km")
          expect(m).to have_key("moving_time_h")
        end
      end

      it "yearly entry has year, count, distance_km, moving_time_h, longest_km, streak" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        data["yearly"].each do |y|
          expect(y).to have_key("year")
          expect(y).to have_key("count")
          expect(y).to have_key("distance_km")
          expect(y).to have_key("moving_time_h")
          expect(y).to have_key("longest_km")
          expect(y).to have_key("streak")
        end
      end

      it "streaks has current and all_time" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        expect(data["streaks"]).to have_key("current")
        expect(data["streaks"]).to have_key("all_time")
      end

      it "activity_types contains sorted distinct categories" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        expect(data["activity_types"]).to eq(%w[ride run])
      end
    end

    context "with empty DB" do
      it "returns 0" do
        expect(stats_exporter.call).to eq(0)
      end

      it "writes empty stats structure" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        expect(data["summary"]).to eq({})
        expect(data["monthly"]).to eq([])
        expect(data["yearly"]).to eq([])
        expect(data["streaks"]).to eq({})
        expect(data["activity_types"]).to eq([])
      end
    end

    context "with single activity" do
      before do
        now = Time.now.utc
        db[:activities].insert(
          run_id: "t1", name: "Solo", distance: 10000, moving_time: 3000,
          sport_category: "walk", start_date: "2024-06-15T01:00:00Z",
          source: "test", created_at: now, updated_at: now
        )
      end

      it "returns 1" do
        expect(stats_exporter.call).to eq(1)
      end

      it "activity_types contains only walk" do
        stats_exporter.call
        data = JSON.parse(File.read(output))
        expect(data["activity_types"]).to eq(["walk"])
      end
    end

    context "with activity filter" do
      subject(:filtered) { described_class.new(db:, output:, activity_filter: ["ride"]) }

      before do
        now = Time.now.utc
        db[:activities].insert(
          run_id: "t1", name: "Run", distance: 5000, moving_time: 1500,
          sport_category: "run", start_date: "2024-06-15T01:00:00Z",
          source: "strava", created_at: now, updated_at: now
        )
        db[:activities].insert(
          run_id: "t2", name: "Ride", distance: 20000, moving_time: 3600,
          sport_category: "ride", start_date: "2024-07-01T01:00:00Z",
          source: "garmin", created_at: now, updated_at: now
        )
      end

      it "filters by sport category" do
        expect(filtered.call).to eq(1)
      end

      it "only ride in breakdown" do
        filtered.call
        data = JSON.parse(File.read(output))
        cats = data["summary"]["sport_breakdown"].map { |b| b["category"] }
        expect(cats).to eq(["ride"])
      end
    end
  end
end

RSpec.describe Workouts::Sync::Strava do
  let(:db) { create_test_db }
  let(:config) { { "client_id" => "x", "client_secret" => "y", "refresh_token" => "z" } }
  subject(:strava) { described_class.new(config:, db:, activity_filter: nil) }

  def create_test_db
    d = Sequel.sqlite
    d.create_table(:activities) do
      Integer :id, primary_key: true
      String :run_id, null: false, unique: true
      String :name; Float :distance; Integer :moving_time; Integer :elapsed_time
      String :sport_category, null: false, default: "run"; String :sport_type
      String :start_date; String :start_date_local; String :location_country
      String :summary_polyline, text: true
      Float :average_heartrate; Float :average_speed; Float :elevation_gain
      String :source
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
    d
  end

  describe "#call" do
    context "without credentials" do
      let(:config) { {} }
      it "returns 0" do
        expect(strava.call).to eq(0)
      end
    end

    context "when token refresh fails" do
      before { allow(strava).to receive(:refresh_access_token).and_return(nil) }
      it "returns 0" do
        expect(strava.call).to eq(0)
      end
    end

    context "with activities to sync" do
      let(:activity) do
        { "id" => 1001, "name" => "Run", "distance" => 5000.0,
          "moving_time" => 1800, "elapsed_time" => 2000,
          "type" => "Run", "start_date" => "2025-01-01T10:00:00Z",
          "start_date_local" => "2025-01-01T18:00:00Z",
          "map" => { "summary_polyline" => "abc" },
          "average_heartrate" => 150, "average_speed" => 2.78,
          "total_elevation_gain" => 50.0 }
      end

      before do
        allow(strava).to receive(:refresh_access_token).and_return("tok123")
        allow(strava).to receive(:fetch_activities).and_return([activity], [])
      end

      it "syncs one activity" do
        expect(strava.call).to eq(1)
      end

      it "inserts into database" do
        strava.call
        expect(db[:activities].count).to eq(1)
        row = db[:activities].first
        expect(row[:run_id]).to eq("strava_1001")
        expect(row[:source]).to eq("strava")
        expect(row[:sport_category]).to eq("run")
      end
    end
  end

  describe "#build_attrs" do
    let(:act) do
      { "id" => 2002, "name" => "Afternoon Ride", "distance" => 20000.0,
        "moving_time" => 3600, "elapsed_time" => 4000,
        "type" => "Ride", "sport_type" => "eBikeRide",
        "start_date" => "2025-06-01T08:00:00Z",
        "start_date_local" => "2025-06-01T16:00:00Z",
        "map" => { "summary_polyline" => "xyz" },
        "total_elevation_gain" => 200.0 }
    end
    subject(:attrs) { strava.send(:build_attrs, act, "ride") }

    it "sets run_id" do
      expect(attrs[:run_id]).to eq("strava_2002")
    end

    it "maps sport_type to category" do
      expect(attrs[:sport_category]).to eq("ride")
    end

    it "uses sport_type over type" do
      expect(attrs[:sport_type]).to eq("ebikeride")
    end

    it "includes polyline" do
      expect(attrs[:summary_polyline]).to eq("xyz")
    end
  end

  describe "#map_sport_type" do
    it "maps eBikeRide to ride" do
      expect(strava.send(:map_sport_type, "Ride", "eBikeRide")).to eq("ride")
    end

    it "falls back to type when sport_type is nil" do
      expect(strava.send(:map_sport_type, "Run", nil)).to eq("run")
    end
  end
end

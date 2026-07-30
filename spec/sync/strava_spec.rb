RSpec.describe Workouts::Sync::Strava do
  let(:db) { create_test_db }
  let(:config) { {"client_id" => "x", "client_secret" => "y", "refresh_token" => "z"} }
  subject(:strava) { described_class.new(config:, db:, activity_filter: nil) }
  let(:tmpdir) { Dir.mktmpdir }

  before do
    allow(strava).to receive(:raw_dir).and_return(File.join(tmpdir, "raw"))
    allow(strava).to receive(:std_dir).and_return(File.join(tmpdir, "std"))
  end

  after { FileUtils.rm_rf(tmpdir) }

  def create_test_db
    d = Sequel.sqlite
    d.create_table(:activities) do
      Integer :id, primary_key: true
      String :run_id, null: false, unique: true
      String :name
      Float :distance
      Integer :moving_time
      Integer :elapsed_time
      String :sport_category, null: false, default: "run"
      String :sport_type
      String :start_date
      String :start_date_local
      String :location_country
      String :summary_polyline, text: true
      Float :average_heartrate
      Float :max_heartrate
      Float :average_cadence
      Float :max_cadence
      Float :average_power
      Float :max_power
      Integer :calories
      Float :average_temperature
      Float :average_speed
      Float :elevation_gain
      String :duplicate_info, text: true
      String :source
      String :external_id
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
        {"id" => 1001, "name" => "Run", "distance" => 5000.0,
         "moving_time" => 1800, "elapsed_time" => 2000,
         "type" => "Run", "start_date" => "2025-01-01T10:00:00Z",
         "start_date_local" => "2025-01-01T18:00:00Z",
         "map" => {"summary_polyline" => "abc"},
         "average_heartrate" => 150, "average_speed" => 2.78,
         "total_elevation_gain" => 50.0, "sport_type" => nil}
      end

      before do
        allow(strava).to receive(:refresh_access_token).and_return("tok123")
        allow(strava).to receive(:fetch_activities).and_return([activity], [])
        allow(strava).to receive(:fetch_detail).and_return(
          JSON.parse(File.read("spec/fixtures/strava/3103806497.json"))
        )
        allow(strava).to receive(:fetch_streams).and_return(
          JSON.parse(File.read("spec/fixtures/strava/streams_3103806497.json"))
        )
        allow(strava).to receive(:report_progress)
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

      it "writes L1 raw file" do
        strava.call
        path = File.join(tmpdir, "raw", "1001.api.json")
        expect(File.exist?(path)).to be true
        content = JSON.parse(File.read(path))
        expect(content).to have_key("detail")
        expect(content).to have_key("streams")
      end

      it "writes L2 standardized view" do
        strava.call
        path = File.join(tmpdir, "std", "1001.json")
        expect(File.exist?(path)).to be true
        content = JSON.parse(File.read(path))
        expect(content).to be_an(Array)
        expect(content.first).to have_key("positionLat")
        expect(content.first).to have_key("positionLong")
      end
    end
  end

  describe "#build_attrs" do
    subject(:attrs) { strava.send(:build_attrs, act, "ride", "poly_abc") }

    it "includes external_id when provided" do
      result = strava.send(:build_attrs, act, "ride", "poly_abc", external_id: "544EA64D-4645-4BBC-9147-638B642FCFE1")
      expect(result[:external_id]).to eq("544EA64D-4645-4BBC-9147-638B642FCFE1")
    end

    it "leaves external_id nil when not provided" do
      expect(attrs[:external_id]).to be_nil
    end
    let(:act) do
      {"id" => 2002, "name" => "Afternoon Ride", "distance" => 20000.0,
       "moving_time" => 3600, "elapsed_time" => 4000,
       "type" => "Ride", "sport_type" => "eBikeRide",
       "start_date" => "2025-06-01T08:00:00Z",
       "start_date_local" => "2025-06-01T16:00:00Z",
       "map" => {"summary_polyline" => "xyz"},
       "average_heartrate" => 145, "max_heartrate" => 172,
       "average_cadence" => 85, "average_watts" => 210,
       "max_watts" => 450, "calories" => 680,
       "average_temp" => 28, "total_elevation_gain" => 200.0}
    end
    it "sets run_id" do
      expect(attrs[:run_id]).to eq("strava_2002")
    end

    it "maps sport_type to category" do
      expect(attrs[:sport_category]).to eq("ride")
    end

    it "uses polyline parameter" do
      expect(attrs[:summary_polyline]).to eq("poly_abc")
    end

    it "maps sensor fields from API summary" do
      expect(attrs[:average_heartrate]).to eq(145)
      expect(attrs[:max_heartrate]).to eq(172)
      expect(attrs[:average_cadence]).to eq(85)
      expect(attrs[:max_cadence]).to be_nil
      expect(attrs[:average_power]).to eq(210)
      expect(attrs[:max_power]).to eq(450)
      expect(attrs[:calories]).to eq(680)
      expect(attrs[:average_temperature]).to eq(28)
    end

    it "leaves sensor fields nil when absent from API" do
      minimal = {"id" => 3003, "type" => "Run"}
      result = strava.send(:build_attrs, minimal, "run")
      expect(result[:average_heartrate]).to be_nil
      expect(result[:max_heartrate]).to be_nil
      expect(result[:average_cadence]).to be_nil
      expect(result[:average_power]).to be_nil
      expect(result[:calories]).to be_nil
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

  describe "#streams_to_l2" do
    let(:detail) { JSON.parse(File.read("spec/fixtures/strava/3103806497.json")) }
    let(:streams) { JSON.parse(File.read("spec/fixtures/strava/streams_3103806497.json")) }
    subject(:l2) { strava.send(:streams_to_l2, detail, streams) }

    it "returns an array of points" do
      expect(l2).to be_an(Array)
      expect(l2.size).to be > 0
    end

    it "each point has positionLat and positionLong" do
      l2.each do |pt|
        expect(pt).to have_key(:positionLat)
        expect(pt).to have_key(:positionLong)
      end
    end

    it "includes altitude when available" do
      has_alt = l2.any? { |pt| !pt[:altitude].nil? }
      expect(has_alt).to be true
    end

    it "coordinates are within China range" do
      l2.each do |pt|
        expect(pt[:positionLat]).to be_between(10, 55)
        expect(pt[:positionLong]).to be_between(70, 140)
      end
    end
  end
end

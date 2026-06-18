RSpec.describe Workouts::Sync::IGPSPORT do
  let(:db) { create_test_db }
  let(:config) { { "phone" => "13800138000", "password" => "pw" } }
  subject(:igp) { described_class.new(config:, db:, activity_filter: nil) }

  def create_test_db
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

  describe "#call" do
    context "without credentials" do
      let(:config) { {} }
      it "returns 0" do
        expect(igp.call).to eq(0)
      end
    end

    context "when login fails" do
      before { allow(igp).to receive(:login).and_return(false) }
      it "returns 0" do
        expect(igp.call).to eq(0)
      end
    end

    context "with activities to sync" do
      let(:activities) { fixture_rows }

      before do
        allow(igp).to receive(:login).and_return(true)
        allow(igp).to receive(:fetch_page).with(1).and_return(activities)
        allow(igp).to receive(:fetch_page).with(2).and_return([])
        allow(igp).to receive(:get_download_url).and_return("https://example.com/fit")
        allow(igp).to receive(:download_fit).and_wrap_original { |_m, _url, id|
          dir = "data/raw/igpsport"
          FileUtils.mkdir_p(dir)
          File.write("#{dir}/#{id}.fit", "")
        }
        allow(Workouts::FIT::Decoder).to receive(:decode).and_return([
          { "positionLat" => 31.0, "positionLong" => 121.0, "timestamp" => 1149593880 }
        ])
        allow(igp).to receive(:write_standardized_json)
        allow(igp).to receive(:report_progress)
      end

      it "syncs all activities" do
        expect(igp.call).to eq(3)
      end

      it "inserts into database" do
        igp.call
        expect(db[:activities].count).to eq(3)
        row = db[:activities].first
        expect(row[:run_id]).to match(/\Aigpsport_\d+\z/)
        expect(row[:source]).to eq("igpsport")
        expect(row[:sport_category]).to eq("ride")
        expect(row[:summary_polyline]).to eq("_ue|D_yoaV")
      end

      it "skips already synced activities" do
        db[:activities].insert(run_id: "igpsport_50279925", source: "igpsport")
        FileUtils.mkdir_p("data/raw/igpsport")
        File.write("data/raw/igpsport/50279925.fit", "")
        expect(igp.call).to eq(2)
      end

      it "skips when download fails" do
        allow(igp).to receive(:get_download_url).and_return(nil)
        expect(igp.call).to eq(0)
      end
    end
  end

  describe "#get_download_url" do
    before do
      resp = instance_double(Faraday::Response, status: 200, body: %<{"data":"https://example.fit"}>)
      allow(Faraday).to receive(:get).and_return(resp)
    end

    it "returns download URL" do
      expect(igp.send(:get_download_url, "12345")).to eq("https://example.fit")
    end
  end

  describe "#build_attrs" do
    subject(:attrs) { igp.send(:build_attrs, row, row["rideId"].to_s, "poly_abc") }
    let(:row) { fixture_rows.first }

    it "sets run_id" do
      expect(attrs[:run_id]).to eq("igpsport_50279925")
    end

    it "has distance" do
      expect(attrs[:distance]).to be_within(0.1).of(2341.77)
    end

    it "has sport_category" do
      expect(attrs[:sport_category]).to eq("ride")
    end

    it "has polyline" do
      expect(attrs[:summary_polyline]).to eq("poly_abc")
    end

    it "has start_date as formatted string" do
      expect(attrs[:start_date]).to be_a(String)
      expect(attrs[:start_date]).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/)
    end
  end

  describe "#map_sport" do
    it "maps known exercise types" do
      expect(igp.send(:map_sport, 0)).to eq("ride")
      expect(igp.send(:map_sport, 1)).to eq("run")
      expect(igp.send(:map_sport, 3)).to eq("walk")
    end

    it "falls back to other for unknown types" do
      expect(igp.send(:map_sport, 99)).to eq("other")
    end
  end

  describe "#parse_date" do
    it "parses standard date string" do
      result = igp.send(:parse_date, "2025-06-01 08:00:00")
      expect(result).to be_a(Time)
      expect(result.strftime("%Y-%m-%d %H:%M:%S")).to eq("2025-06-01 08:00:00")
    end

    it "normalizes dot separator" do
      result = igp.send(:parse_date, "2025.06.01 08:00:00")
      expect(result).to be_a(Time)
      expect(result.strftime("%Y-%m-%d %H:%M:%S")).to eq("2025-06-01 08:00:00")
    end

    it "returns nil for nil" do
      expect(igp.send(:parse_date, nil)).to be_nil
    end
  end

  def fixture_rows
    @fixture_rows ||= JSON.parse(load_fixture("igpsport/activities_page.json")).dig("data", "rows")
  end
end

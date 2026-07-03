RSpec.describe Workouts::Sync::XOSS do
  let(:db) { create_test_db }
  let(:token_path) { File.join(Dir.mktmpdir, "xoss_tokens.json") }
  let(:config) { { "email" => "test@xoss.com", "password" => "pw", "token_path" => token_path } }
  subject(:xoss) { described_class.new(config:, db:, activity_filter: nil) }

  let(:activity) do
    { "id" => 3001, "title" => "XOSS Ride", "sport" => 2,
      "distance" => 15000.0, "duration" => 2400,
      "start_timestamp" => 1700000000, "sub_sport" => 0,
      "fit_file_hash" => nil,
      "total_calories" => nil }
  end

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
        expect(xoss.call).to eq(0)
      end
    end

    context "when login fails" do
      before do
        allow(xoss).to receive(:load_tokens).and_return(false)
        allow(xoss).to receive(:refresh_access_token).and_return(false)
        allow(xoss).to receive(:login).and_return(false)
      end
      it "returns 0" do
        expect(xoss.call).to eq(0)
      end
    end

    context "with activities to sync" do
      let(:activities) { [activity] }

      before do
        allow(xoss).to receive(:login).and_return(true)
        allow(xoss).to receive(:fetch_page).with(1, 50).and_return(activities)
        allow(xoss).to receive(:fetch_page).with(51, 50).and_return(nil)
        allow(xoss).to receive(:report_progress)
      end

      it "syncs one activity" do
        expect(xoss.call).to eq(1)
      end

      it "inserts into database" do
        xoss.call
        expect(db[:activities].count).to eq(1)
        row = db[:activities].first
        expect(row[:run_id]).to eq("xoss_3001")
        expect(row[:source]).to eq("xoss")
        expect(row[:sport_category]).to eq("ride")
      end
    end

    context "with existing records and raw files" do
      let(:existing_activity) do
        { "id" => 3001, "title" => "XOSS Ride", "sport" => 2,
          "distance" => 15000.0, "duration" => 2400,
          "start_timestamp" => 1700000000, "sub_sport" => 0,
          "fit_file_hash" => "00000000-0000-0000-0000-000000000000" }
      end

      before do
        db[:activities].insert(run_id: "xoss_3001", name: "old", sport_category: "ride",
          source: "xoss", start_date: "2023-01-01")
        allow(xoss).to receive(:login).and_return(true)
        allow(xoss).to receive(:fetch_page).with(1, 50).and_return([existing_activity])
        allow(xoss).to receive(:fetch_page).with(51, 50).and_return(nil)
        allow(xoss).to receive(:report_progress)
      end

      it "skips when raw file exists" do
        allow(xoss).to receive(:raw_file_exists?).with("3001").and_return(true)
        expect(xoss.call).to eq(0)
      end

      it "backfills when raw file missing" do
        allow(xoss).to receive(:raw_file_exists?).with("3001").and_return(false)
        allow(xoss).to receive(:download_fit).and_return("fake_fit")
        allow(xoss).to receive(:write_raw)
        fixture_path = "spec/fixtures/xoss/fit_sample.56751769.fit"
        wgs = Workouts::FIT::Decoder.decode(fixture_path)
        allow(Workouts::FIT::Decoder).to receive(:decode).and_return(wgs)
        expect(xoss.call).to eq(1)
        row = db[:activities].where(run_id: "xoss_3001").first
        expect(row[:summary_polyline]).not_to be_nil
      end
    end

    context "when time budget expires" do
      let(:activities) { [activity, activity.merge("id" => 3002)] }

      before do
        allow(xoss).to receive(:login).and_return(true)
        allow(xoss).to receive(:fetch_page).with(1, 50).and_return(activities)
        allow(xoss).to receive(:fetch_page).with(51, 50).and_return(nil)
        allow(xoss).to receive(:report_progress)
        allow(xoss).to receive(:time_expired?).and_return(true)
      end

      it "stops processing after time budget" do
        expect(xoss.call).to eq(0)
      end
    end

    context "with skip_type filter" do
      subject(:xoss) { described_class.new(config:, db:, activity_filter: ["run"]) }
      let(:activities) { [activity] }

      before do
        allow(xoss).to receive(:login).and_return(true)
        allow(xoss).to receive(:fetch_page).with(1, 50).and_return(activities)
        allow(xoss).to receive(:fetch_page).with(51, 50).and_return(nil)
        allow(xoss).to receive(:report_progress)
      end

      it "skips non-matching sport types" do
        expect(xoss.call).to eq(0)
      end
    end
  end

  describe "#process_activity" do
    context "with FIT file hash" do
      let(:activity) do
        { "id" => 3001, "title" => "XOSS Ride", "sport" => 2,
          "distance" => 15000.0, "duration" => 2400,
          "start_timestamp" => 1700000000, "sub_sport" => 0,
          "fit_file_hash" => "00000000-0000-0000-0000-000000000000" }
      end

      before do
        xoss.instance_variable_set(:@auth_headers, { "Authorization" => "Bearer test" })
      end

      it "downloads and decodes FIT when hash is present" do
        allow(xoss).to receive(:download_fit).with("3001").and_return("fake_fit_binary")
        expect(xoss).to receive(:write_raw).with("fake_fit_binary", "3001")
        fixture_path = "spec/fixtures/xoss/fit_sample.56751769.fit"
        wgs = Workouts::FIT::Decoder.decode(fixture_path)
        allow(Workouts::FIT::Decoder).to receive(:decode).and_return(wgs)
        expect(xoss).to receive(:write_std)
        result = xoss.send(:process_activity, activity)
        expect(result[:summary_polyline]).not_to be_nil
        expect(result[:calories]).to be_nil
      end

      it "handles FIT decode failure gracefully" do
        allow(xoss).to receive(:download_fit).with("3001").and_return("fake_fit_binary")
        allow(Workouts::FIT::Decoder).to receive(:decode).and_raise(StandardError, "corrupt")
        expect { xoss.send(:process_activity, activity) }.not_to raise_error
      end
    end

    context "with total_calories" do
      let(:activity) do
        { "id" => 3001, "title" => "XOSS Ride", "sport" => 2,
          "distance" => 15000.0, "duration" => 2400,
          "start_timestamp" => 1700000000, "sub_sport" => 0,
          "fit_file_hash" => nil,
          "total_calories" => 350 }
      end

      before do
        allow(xoss).to receive(:login).and_return(true)
        xoss.send(:authenticate)
      end

      it "captures calories from API" do
        result = xoss.send(:process_activity, activity)
        expect(result[:calories]).to eq(350)
      end
    end

    context "without FIT file hash" do
      let(:activity) do
        { "id" => 3001, "title" => "XOSS Ride", "sport" => 2,
          "distance" => 15000.0, "duration" => 2400,
          "start_timestamp" => 1700000000, "sub_sport" => 0,
          "fit_file_hash" => nil }
      end

      before do
        allow(xoss).to receive(:login).and_return(true)
        xoss.send(:authenticate)
      end

      it "skips FIT download" do
        expect(xoss).not_to receive(:download_fit)
        xoss.send(:process_activity, activity)
      end
    end

    context "with empty fit_file_hash" do
      let(:activity) do
        { "id" => 3001, "title" => "XOSS Ride", "sport" => 2,
          "distance" => 15000.0, "duration" => 2400,
          "start_timestamp" => 1700000000, "sub_sport" => 0,
          "fit_file_hash" => "" }
      end

      before do
        allow(xoss).to receive(:login).and_return(true)
        xoss.send(:authenticate)
      end

      it "skips FIT download for empty string" do
        expect(xoss).not_to receive(:download_fit)
        xoss.send(:process_activity, activity)
      end
    end
  end

  describe "#compute_sensor_summary" do
    it "returns empty hash for empty records" do
      expect(xoss.send(:compute_sensor_summary, [])).to eq({})
    end

    it "returns averages from decoded FIT records" do
      records = [
        { "temperature" => 20, "cadence" => 80, "power" => 150, "heart_rate" => 140 },
        { "temperature" => 22, "cadence" => 85, "power" => 200, "heart_rate" => 155 }
      ]
      result = xoss.send(:compute_sensor_summary, records)
      expect(result[:average_temperature]).to eq(21.0)
      expect(result[:average_cadence]).to eq(82.5)
      expect(result[:average_power]).to eq(175.0)
      expect(result[:average_heartrate]).to eq(147.5)
      expect(result[:max_cadence]).to eq(85)
      expect(result[:max_power]).to eq(200)
    end

    it "handles partial sensor data" do
      records = [
        { "temperature" => 20, "cadence" => nil, "power" => 150, "heart_rate" => nil },
        { "temperature" => nil, "cadence" => 85, "power" => nil, "heart_rate" => 155 }
      ]
      result = xoss.send(:compute_sensor_summary, records)
      expect(result[:average_temperature]).to eq(20.0)
      expect(result[:average_cadence]).to eq(85.0)
    end
  end

  describe "#download_fit" do
    let(:redirect_url) { "https://oss.example.com/fit/test.fit?Signature=abc&Expires=9999999999" }

    before do
      allow(xoss).to receive(:login).and_return(true)
      xoss.send(:authenticate)
    end

    it "follows 302 redirect and returns body" do
      stub_request = instance_double(Net::HTTP::Get)
      redirect_resp = instance_double(Net::HTTPResponse, code: "302", :[] => redirect_url)
      fit_resp = instance_double(Net::HTTPResponse, code: "200", body: "fake_fit_content")

      expect(xoss).to receive(:http_request)
        .with(:get, "/api/v3/activity/3001/fit_file/", headers: anything)
        .and_return(redirect_resp)

      http_instance = instance_double(Net::HTTP)
      expect(Net::HTTP).to receive(:new).with("oss.example.com", 443).and_return(http_instance)
      expect(http_instance).to receive(:use_ssl=).with(true)
      expect(http_instance).to receive(:open_timeout=).with(60)
      expect(http_instance).to receive(:read_timeout=).with(180)
      expect(http_instance).to receive(:start).and_yield(http_instance)
      expect(http_instance).to receive(:request).with(instance_of(Net::HTTP::Get)).and_return(fit_resp)

      expect(xoss.send(:download_fit, "3001")).to eq("fake_fit_content")
    end

    it "returns nil on non-302" do
      resp = instance_double(Net::HTTPResponse, code: "404")
      expect(xoss).to receive(:http_request).and_return(resp)
      expect(xoss.send(:download_fit, "3001")).to be_nil
    end
  end

  describe "#write_raw" do
    around { |e| Dir.mktmpdir { |dir| @tmpdir = dir; e.run } }

    before do
      allow(xoss).to receive(:raw_dir).and_return(@tmpdir)
    end

    it "writes binary FIT file atomically" do
      xoss.send(:write_raw, "fake_binary", "3001")
      path = File.join(@tmpdir, "3001.fit")
      expect(File.exist?(path)).to be true
      expect(File.read(path, mode: "rb")).to eq("fake_binary")
    end
  end

  describe "#write_std" do
    around { |e| Dir.mktmpdir { |dir| @tmpdir = dir; e.run } }

    before do
      allow(xoss).to receive(:std_dir).and_return(@tmpdir)
    end

    it "writes standardized GPS JSON" do
      points = [{ "positionLat" => 36.75, "positionLong" => 114.95 }]
      xoss.send(:write_std, points, "3001")
      path = File.join(@tmpdir, "3001.json")
      expect(File.exist?(path)).to be true
      expect(JSON.parse(File.read(path))).to eq(points)
    end
  end

  describe "#map_sport" do
    it "maps known sport codes" do
      expect(xoss.send(:map_sport, 1)).to eq("run")
      expect(xoss.send(:map_sport, 2)).to eq("ride")
      expect(xoss.send(:map_sport, 11)).to eq("walk")
    end

    it "falls back to other for unknown codes" do
      expect(xoss.send(:map_sport, 99)).to eq("other")
    end
  end

  describe "#existing_run_ids" do
    before do
      db[:activities].insert(run_id: "xoss_100", name: "a", source: "xoss", start_date: "2023-01-01")
      db[:activities].insert(run_id: "xoss_200", name: "b", source: "xoss", start_date: "2023-01-02")
    end

    it "returns all xoss run_ids without prefix" do
      expect(xoss.send(:existing_run_ids)).to contain_exactly("100", "200")
    end
  end
end
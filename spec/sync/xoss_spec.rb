RSpec.describe Workouts::Sync::XOSS do
  let(:db) { create_test_db }
  let(:token_path) { File.join(Dir.mktmpdir, "xoss_tokens.json") }
  let(:config) { {"email" => "test@xoss.com", "password" => "pw", "token_path" => token_path} }
  subject(:xoss) { described_class.new(config:, db:, activity_filter: nil) }

  # Load fixtures once
  let(:login_response) { JSON.parse(File.read("spec/fixtures/xoss/login_response.json")) }
  let(:activity_list_response) { JSON.parse(File.read("spec/fixtures/xoss/activity_list_page.json")) }
  let(:fit_fixture_path) { "spec/fixtures/xoss/fit_sample.56751769.fit" }
  let(:fit_bytes) { File.read(fit_fixture_path, mode: "rb") }
  let(:wgs_points) { Workouts::FIT::Decoder.decode(fit_fixture_path) }

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
      String :source
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
    d
  end

  def stub_api_responses
    login_resp = instance_double(Net::HTTPResponse, code: "200", body: login_response.to_json)
    allow(login_resp).to receive(:[]).with("set-cookie").and_return(nil)

    list_resp = instance_double(Net::HTTPResponse, code: "200", body: activity_list_response.to_json)
    empty_resp = instance_double(Net::HTTPResponse, code: "200", body: '{"code":0,"data":{"results":[]}}')
    allow(xoss).to receive(:http_request) do |method, path, **|
      if path == "/api/v1/jwt-token/" && method == :post
        login_resp
      elsif path == "/api/v3/activity/" && method == :get
        # First call (offset=1) returns fixture, subsequent calls return empty
        @_call_count ||= 0
        @_call_count += 1
        (@_call_count == 1) ? list_resp : empty_resp
      end
    end
  end

  describe "#call" do
    context "without credentials" do
      let(:config) { {} }
      it "returns 0" do
        expect(xoss.call).to eq(0)
      end
    end

    context "with fixture API responses" do
      before do
        stub_api_responses
        allow(xoss).to receive(:report_progress)
      end

      it "syncs activities from fixture data" do
        allow(xoss).to receive(:download_fit).and_return(nil)
        expect(xoss.call).to eq(2)
      end

      it "inserts into database with fields from fixture" do
        allow(xoss).to receive(:download_fit).and_return(nil)
        xoss.call
        rows = db[:activities].where(source: "xoss").order(:run_id).all
        expect(rows.size).to eq(2)
        expect(rows.first[:run_id]).to eq("xoss_3001")
        expect(rows.first[:sport_category]).to eq("ride")
        expect(rows.first[:start_date]).to eq("2025-10-31T06:29:33Z")
        expect(rows.first[:distance]).to eq(606.43)
        expect(rows.first[:elevation_gain]).to be_nil
      end
    end

    context "when login returns non-200" do
      let(:error_body) { File.read("spec/fixtures/xoss/login_error_response.json") }

      before do
        resp = instance_double(Net::HTTPResponse, code: "400", body: error_body)
        allow(xoss).to receive(:http_request).and_return(resp)
      end

      it "returns 0" do
        expect(xoss.call).to eq(0)
      end
    end

    context "when login returns 200 with error code" do
      let(:error_body) { File.read("spec/fixtures/xoss/login_error_response.json") }

      before do
        resp = instance_double(Net::HTTPResponse, code: "200", body: error_body)
        allow(xoss).to receive(:http_request).and_return(resp)
      end

      it "returns 0 for code != 0" do
        expect(xoss.call).to eq(0)
      end
    end

    context "with existing records and raw files" do
      before do
        db[:activities].insert(run_id: "xoss_3001", name: "old", sport_category: "ride",
          source: "xoss", start_date: "2023-01-01")
        db[:activities].insert(run_id: "xoss_3002", name: "old", sport_category: "ride",
          source: "xoss", start_date: "2023-01-02")
        stub_api_responses
        allow(xoss).to receive(:report_progress)
      end

      it "skips when raw file exists" do
        allow(xoss).to receive(:raw_file_exists?).and_return(true)
        expect(xoss.call).to eq(0)
      end

      it "backfills when raw file missing, using real FIT" do
        allow(xoss).to receive(:raw_file_exists?).and_return(false)
        allow(xoss).to receive(:download_fit).and_return(fit_bytes)
        allow(Workouts::FIT::Decoder).to receive(:decode).with(anything).and_return(wgs_points)
        expect(xoss.call).to eq(2)
        row = db[:activities].where(run_id: "xoss_3001").first
        expect(row[:summary_polyline]).not_to be_nil
        expect(row[:average_temperature]).to eq(16.2)
      end
    end

    context "with skip_type filter" do
      subject(:xoss) { described_class.new(config:, db:, activity_filter: ["run"]) }

      before do
        stub_api_responses
        allow(xoss).to receive(:report_progress)
      end

      it "skips ride activity" do
        allow(xoss).to receive(:download_fit).and_return(nil)
        expect(xoss.call).to eq(0)
      end
    end
  end

  describe "#resolve_local_time" do
    before do
      xoss.instance_variable_set(:@auth_headers, {"Authorization" => "Bearer test"})
    end

    it "returns local time with offset when GPS points available" do
      stub_finder = double("TimezoneFinder")
      allow(stub_finder).to receive(:timezone_at).with(lat: 36.76, lng: 117.0).and_return("Asia/Shanghai")
      xoss.instance_variable_set(:@tz_resolver,
        Workouts::Timezone::Resolver.new({}, finder: stub_finder))

      start_utc = Time.parse("2025-10-31T06:29:33Z")
      wgs = [{"positionLat" => 36.76, "positionLong" => 117.0}]
      result = xoss.send(:resolve_local_time, start_utc, wgs)
      expect(result).to eq("2025-10-31T14:29:33+08:00")
    end

    it "returns UTC when no GPS points" do
      start_utc = Time.parse("2025-10-31T06:29:33Z")
      result = xoss.send(:resolve_local_time, start_utc, [])
      expect(result).to eq("2025-10-31T06:29:33Z")
    end

    it "returns UTC when no FIT data (no wgs_points)" do
      start_utc = Time.parse("2025-10-31T06:29:33Z")
      result = xoss.send(:resolve_local_time, start_utc, nil)
      expect(result).to eq("2025-10-31T06:29:33Z")
    end
  end

  describe "#process_activity" do
    let(:activity) { activity_list_response.dig("data", "results", 0) }

    before do
      xoss.instance_variable_set(:@auth_headers, {"Authorization" => "Bearer test"})
    end

    it "downloads and decodes FIT, writes std, produces polyline" do
      expect(xoss).to receive(:download_fit).with("3001").and_return(fit_bytes)
      expect(xoss).to receive(:write_raw).with(fit_bytes, "3001")
      allow(Workouts::FIT::Decoder).to receive(:decode).and_return(wgs_points)
      expect(xoss).to receive(:write_std).with(wgs_points, "3001")
      result = xoss.send(:process_activity, activity)
      expect(result[:summary_polyline]).not_to be_nil
      first_pt = Workouts::Geo::Polyline.decode(result[:summary_polyline]).first
      expect(first_pt[0]).to be_within(0.01).of(36.76)
      expect(result[:calories]).to eq(14)
      expect(result[:average_temperature]).to eq(16.2)
    end

    it "handles FIT decode failure gracefully" do
      allow(xoss).to receive(:download_fit).and_return(fit_bytes)
      allow(Workouts::FIT::Decoder).to receive(:decode).and_raise(StandardError, "corrupt")
      expect { xoss.send(:process_activity, activity) }.not_to raise_error
    end

    it "skips FIT download when no fit_file_hash" do
      bare = activity.reject { |k| k == "fit_file_hash" }
      expect(xoss).not_to receive(:download_fit)
      xoss.send(:process_activity, bare)
    end

    it "skips FIT download when fit_file_hash is empty" do
      bare = activity.merge("fit_file_hash" => "")
      expect(xoss).not_to receive(:download_fit)
      xoss.send(:process_activity, bare)
    end

    it "produces start_date_local with timezone offset when FIT has GPS" do
      stub_finder = double("TimezoneFinder")
      allow(stub_finder).to receive(:timezone_at).and_return("Asia/Shanghai")
      xoss.instance_variable_set(:@tz_resolver,
        Workouts::Timezone::Resolver.new({}, finder: stub_finder))

      expect(xoss).to receive(:download_fit).with("3001").and_return(fit_bytes)
      expect(xoss).to receive(:write_raw).with(fit_bytes, "3001")
      allow(Workouts::FIT::Decoder).to receive(:decode).and_return(wgs_points)
      result = xoss.send(:process_activity, activity)

      expect(result[:start_date]).to eq("2025-10-31T06:29:33Z")  # UTC
      expect(result[:start_date_local]).to eq("2025-10-31T14:29:33+08:00")  # UTC+8
    end

    it "keeps start_date_local as UTC when no FIT data" do
      bare = activity.reject { |k| k == "fit_file_hash" }
      result = xoss.send(:process_activity, bare)
      expect(result[:start_date]).to eq("2025-10-31T06:29:33Z")
      expect(result[:start_date_local]).to eq("2025-10-31T06:29:33Z")
    end
  end

  describe "#download_fit" do
    it "returns nil on non-302" do
      resp = instance_double(Net::HTTPResponse, code: "404")
      allow(xoss).to receive(:http_request).and_return(resp)
      expect(xoss.send(:download_fit, "3001")).to be_nil
    end

    it "follows 302 redirect via http_request and returns body" do
      oss_url = "https://oss.example.com/fit/test.fit?Signature=abc"
      resp302 = instance_double(Net::HTTPResponse, code: "302")
      allow(resp302).to receive(:[]).with("location").and_return(oss_url)
      allow(xoss).to receive(:http_request).and_return(resp302)

      fit_resp = instance_double(Net::HTTPResponse, code: "200", body: "FIT_BODY")
      http_double = instance_double(Net::HTTP)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:start).and_yield(http_double)
      allow(http_double).to receive(:request).and_return(fit_resp)

      expect(xoss.send(:download_fit, "3001")).to eq("FIT_BODY")
    end
  end

  describe "#write_raw" do
    it "writes binary FIT file atomically via temp→rename" do
      path = xoss.send(:raw_path, "3001")
      xoss.send(:write_raw, fit_bytes, "3001")
      expect(File.exist?(path)).to be true
      expect(File.read(path, mode: "rb")).to eq(fit_bytes)
      expect(Dir.glob(File.join(xoss.send(:raw_dir), ".*.fit.tmp")).size).to eq(0)
    end
  end

  describe "#write_std" do
    it "writes standardized GPS JSON" do
      path = xoss.send(:std_path, "3001")
      xoss.send(:write_std, wgs_points, "3001")
      expect(File.exist?(path)).to be true
      written = JSON.parse(File.read(path))
      expect(written.size).to eq(268)
      expect(written.first["positionLat"]).to be_within(0.01).of(36.76)
      expect(Dir.glob(File.join(xoss.send(:std_dir), ".*.json.tmp")).size).to eq(0)
    end
  end

  describe "#compute_sensor_summary" do
    it "returns empty hash for empty records" do
      expect(xoss.send(:compute_sensor_summary, [])).to eq({})
    end

    it "computes averages from real FIT fixture" do
      result = xoss.send(:compute_sensor_summary, wgs_points)
      expect(result[:average_temperature]).to eq(16.2)
      expect(result[:average_cadence]).to be_nil
      expect(result[:average_heartrate]).to be_nil
    end

    it "handles partial sensor data" do
      records = [
        {"temperature" => 20, "cadence" => nil, "heart_rate" => nil},
        {"temperature" => nil, "cadence" => 85, "heart_rate" => 155}
      ]
      result = xoss.send(:compute_sensor_summary, records)
      expect(result[:average_temperature]).to eq(20.0)
      expect(result[:average_cadence]).to eq(85.0)
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

    it "returns all ids without prefix" do
      expect(xoss.send(:existing_run_ids)).to contain_exactly("100", "200")
    end
  end
end

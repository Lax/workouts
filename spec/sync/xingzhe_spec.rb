RSpec.describe Workouts::Sync::XingZhe do
  let(:db) { create_test_db }
  let(:config) { { "email" => "test@xz.com", "password" => "pw" } }
  subject(:xz) { described_class.new(config:, db:, activity_filter: nil) }

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
        expect(xz.call).to eq(0)
      end
    end

    context "when login fails" do
      before { allow(xz).to receive(:login).and_return(false) }
      it "returns 0" do
        expect(xz.call).to eq(0)
      end
    end

    context "with activities to sync" do
      let(:activities) do
        [{ "id" => 4001, "title" => "XZ Hike", "sport" => 2,
           "distance" => 5000.0, "duration" => 3600,
           "start_time" => 1700000000000, "avg_speed" => 5.0,
           "elevation_gain" => 300.0 }]
      end

      before do
        allow(xz).to receive(:login).and_return(true)
        allow(xz).to receive(:fetch_page).with(0, 50).and_return(activities)
        allow(xz).to receive(:fetch_page).with(50, 50).and_return(nil)
        allow(xz).to receive(:report_progress)
        allow(xz).to receive(:fetch_stream).and_return(nil)
        allow(xz).to receive(:fetch_activity_detail).and_return(nil)
      end

      it "syncs one activity" do
        expect(xz.call).to eq(1)
      end

      it "inserts into database" do
        xz.call
        expect(db[:activities].count).to eq(1)
        row = db[:activities].first
        expect(row[:run_id]).to eq("xingzhe_4001")
        expect(row[:source]).to eq("xingzhe")
        expect(row[:sport_category]).to eq("hike")
      end

      context "and stream returns location data" do
        let(:stream_data) do
          { "location" => [[116.0, 40.0], [116.002, 40.001], [116.005, 40.003]],
            "timestamp" => [1000000.0, 1000010.0, 1000020.0],
            "altitude" => [10.0, 11.0, 12.0],
            "speed" => [3.0, 3.1, 3.2],
            "distance" => [0.0, 100.0, 200.0] }
        end

        before do
          allow(xz).to receive(:fetch_stream).with("4001").and_return(stream_data)
          allow(xz).to receive(:write_raw)
          allow(xz).to receive(:write_std)
        end

        it "generates summary_polyline from stream location" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).not_to be_nil
          expect(row[:summary_polyline]).not_to be_empty

          decoded = Workouts::Geo::Polyline.decode(row[:summary_polyline])
          expect(decoded.size).to eq(3)
          expect(decoded[0][0]).to be_within(1e-5).of(40.0)
          expect(decoded[0][1]).to be_within(1e-5).of(116.0)
        end

        it "calls write_raw with stream data" do
          expect(xz).to receive(:write_raw).with(stream_data, "4001")
          xz.call
        end

        it "calls write_std with swapped lat/lng" do
          expect(xz).to receive(:write_std) do |pts, _stream, _id|
            expect(pts).to eq([[40.0, 116.0], [40.001, 116.002], [40.003, 116.005]])
          end
          xz.call
        end
      end

      context "and stream returns empty location" do
        before do
          allow(xz).to receive(:fetch_stream).with("4001").and_return({ "location" => [] })
          allow(xz).to receive(:fetch_activity_detail).with("4001").and_return(nil)
        end

        it "inserts without polyline" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).to be_nil
        end
      end

      context "and stream returns single point" do
        before do
          allow(xz).to receive(:fetch_stream).with("4001")
            .and_return({ "location" => [[116.0, 40.0]] })
          allow(xz).to receive(:write_raw)
          allow(xz).to receive(:write_std)
          allow(xz).to receive(:fetch_activity_detail).with("4001").and_return(nil)
        end

        it "inserts without polyline (guard: pts.size < 2)" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).to be_nil
        end
      end

      context "and stream returns single point with segments_km fallback" do
        let(:detail_data) do
          { "segments_km" => [
            { "latitude" => 40.0, "longitude" => 116.0 },
            { "latitude" => 40.001, "longitude" => 116.002 },
          ] }
        end

        before do
          allow(xz).to receive(:fetch_stream).with("4001")
            .and_return({ "location" => [[116.0, 40.0]] })
          allow(xz).to receive(:write_raw)
          allow(xz).to receive(:fetch_activity_detail).with("4001").and_return(detail_data)
        end

        it "falls back to segments_km polyline (not blocked by stream if)" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).not_to be_nil
        end
      end

      context "and stream returns nil (API failure)" do
        before do
          allow(xz).to receive(:fetch_stream).with("4001").and_return(nil)
          allow(xz).to receive(:fetch_activity_detail).with("4001").and_return(nil)
        end

        it "inserts without polyline" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).to be_nil
        end
      end

      context "and stream fails with segments_km fallback" do
        let(:detail_data) do
          { "segments_km" => [
            { "latitude" => 40.0, "longitude" => 116.0 },
            { "latitude" => 40.001, "longitude" => 116.002 },
            { "latitude" => 40.003, "longitude" => 116.005 }
          ] }
        end

        before do
          allow(xz).to receive(:fetch_stream).with("4001").and_return(nil)
          allow(xz).to receive(:fetch_activity_detail).with("4001").and_return(detail_data)
        end

        it "falls back to segments_km polyline" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).not_to be_nil

          decoded = Workouts::Geo::Polyline.decode(row[:summary_polyline])
          expect(decoded.size).to eq(3)
        end
      end

      context "and detail api returns without segments_km" do
        before do
          allow(xz).to receive(:fetch_stream).with("4001").and_return(nil)
          allow(xz).to receive(:fetch_activity_detail).with("4001").and_return({})
        end

        it "inserts without summary_polyline" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).to be_nil
        end
      end

      context "and detail api fails" do
        before do
          allow(xz).to receive(:fetch_stream).with("4001").and_return(nil)
          allow(xz).to receive(:fetch_activity_detail).with("4001").and_return(nil)
        end

        it "inserts without summary_polyline" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).to be_nil
        end
      end

      context "when both DB and raw file exist" do
        before do
          db[:activities].insert(run_id: "xingzhe_4001", source: "xingzhe")
          FileUtils.mkdir_p("data/raw/xingzhe")
          File.write("data/raw/xingzhe/4001.json", "{}")
          allow(xz).to receive(:fetch_page).with(0, 50).and_return(activities)
          allow(xz).to receive(:fetch_page).with(50, 50).and_return(nil)
        end

        after do
          FileUtils.rm_rf("data/raw/xingzhe")
        end

        it "skips the activity" do
          expect(xz.call).to eq(0)
        end

        it "does not call fetch_stream" do
          expect(xz).not_to receive(:fetch_stream)
          xz.call
        end
      end

      context "when DB exists but raw file missing (missing_raw backfill)" do
        let(:stream_data) do
          { "location" => [[116.0, 40.0], [116.002, 40.001]] }
        end

        before do
          db[:activities].insert(run_id: "xingzhe_4001", source: "xingzhe")
          allow(xz).to receive(:fetch_stream) { |arg| arg == "4001" ? stream_data : nil }
          allow(xz).to receive(:write_raw)
          allow(xz).to receive(:write_std)
        end

        it "re-processes and updates polyline" do
          expect(xz.call).to eq(1)
          row = db[:activities].first
          expect(row[:summary_polyline]).not_to be_nil
        end
      end
    end

    context "when time budget is expired" do
      subject(:xz) { described_class.new(config:, db:, activity_filter: nil, time_budget: 1) }
      let(:activities) do
        [{ "id" => 4001, "title" => "XZ Hike", "sport" => 2,
           "distance" => 5000.0, "duration" => 3600,
           "start_time" => 1700000000000, "avg_speed" => 5.0,
           "elevation_gain" => 300.0 }]
      end

      before do
        allow(xz).to receive(:login).and_return(true)
        allow(xz).to receive(:fetch_page).with(0, 50).and_return(activities)
        allow(xz).to receive(:fetch_page).with(50, 50).and_return(nil)
        allow(xz).to receive(:fetch_stream).and_return(nil)
        allow(xz).to receive(:time_expired?).and_return(true)
      end

      it "honors time budget (stops before processing)" do
        expect(xz.call).to eq(0)
      end
    end
  end

  describe "#map_sport" do
    it "maps known sport codes" do
      expect(xz.send(:map_sport, 1)).to eq("run")
      expect(xz.send(:map_sport, 3)).to eq("ride")
      expect(xz.send(:map_sport, 6)).to eq("walk")
    end

    it "falls back to other for unknown codes" do
      expect(xz.send(:map_sport, 99)).to eq("other")
    end
  end

  describe "#extract_cookie" do
    it "extracts sessionid from set-cookie header" do
      resp = instance_double(Net::HTTPResponse)
      allow(resp).to receive(:[]).with("set-cookie").and_return("sessionid=abc123; path=/")
      expect(xz.send(:extract_cookie, resp)).to eq("sessionid=abc123")
    end

    it "returns nil when no set-cookie" do
      resp = instance_double(Net::HTTPResponse)
      allow(resp).to receive(:[]).with("set-cookie").and_return(nil)
      expect(xz.send(:extract_cookie, resp)).to be_nil
    end
  end

  describe "#raw_path" do
    it "returns path with json extension" do
      expect(xz.send(:raw_path, "12345")).to end_with("12345.json")
    end
  end

  describe "#stream_to_polyline" do
    let(:raw_content) do
      { "source" => "xingzhe", "stream" => {
        "location" => [[116.0, 40.0], [116.002, 40.001]],
        "timestamp" => [1000000.0, 1000010.0],
        "altitude" => [10.0, 11.0]
      } }
    end

    after { FileUtils.rm_rf("data/raw/xingzhe") }

    it "reads raw file and returns encoded polyline" do
      FileUtils.mkdir_p("data/raw/xingzhe")
      File.write("data/raw/xingzhe/test999.json", JSON.generate(raw_content))
      result = xz.send(:stream_to_polyline, "test999")
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "swaps [lng, lat] to [lat, lng]" do
      FileUtils.mkdir_p("data/raw/xingzhe")
      File.write("data/raw/xingzhe/test999.json", JSON.generate(raw_content))
      result = xz.send(:stream_to_polyline, "test999")
      decoded = Workouts::Geo::Polyline.decode(result)
      expect(decoded[0][0]).to be_within(1e-5).of(40.0)
      expect(decoded[0][1]).to be_within(1e-5).of(116.0)
      expect(decoded[1][0]).to be_within(1e-5).of(40.001)
      expect(decoded[1][1]).to be_within(1e-5).of(116.002)
    end

    it "returns nil when raw file missing" do
      expect(xz.send(:stream_to_polyline, "nonexistent")).to be_nil
    end

    it "returns nil when single location point" do
      content = raw_content.dup
      content["stream"] = content["stream"].merge("location" => [[116.0, 40.0]])
      FileUtils.mkdir_p("data/raw/xingzhe")
      File.write("data/raw/xingzhe/test999.json", JSON.generate(content))
      expect(xz.send(:stream_to_polyline, "test999")).to be_nil
    end
  end

  describe "#fetch_stream" do
    it "passes headers to http_request" do
      resp = instance_double(Net::HTTPResponse, code: "401")
      expect(xz).to receive(:http_request)
        .with(:get, "/api/v1/pgworkout/12345/stream/", headers: instance_of(Hash))
        .and_return(resp)
      xz.send(:fetch_stream, "12345")
    end
  end

  describe "#write_raw" do
    let(:stream) { { "location" => [[116.0, 40.0]] } }

    after { FileUtils.rm_rf("data/raw/xingzhe") }

    it "writes JSON file with source and stream" do
      xz.send(:write_raw, stream, "test123")
      path = "data/raw/xingzhe/test123.json"
      expect(File.exist?(path)).to be true
      data = JSON.parse(File.read(path))
      expect(data["source"]).to eq("xingzhe")
      expect(data["stream"]).to eq(stream)
      expect(data["fetchedAt"]).to be_a(String)
    end
  end

  describe "#write_std" do
    let(:pts) { [[40.0, 116.0], [40.001, 116.002]] }
    let(:stream) do
      { "timestamp" => [1000000.0, 1000010.0],
        "altitude" => [10.0, 11.0],
        "speed" => [3.0, 3.1],
        "distance" => [0.0, 100.0] }
    end

    after { FileUtils.rm_rf("data/std/xingzhe") }

    it "writes JSON array with lat/lng/alt/ts/speed/distance" do
      xz.send(:write_std, pts, stream, "test456")
      path = "data/std/xingzhe/test456.json"
      expect(File.exist?(path)).to be true
      data = JSON.parse(File.read(path))
      expect(data.size).to eq(2)
      expect(data[0]["latitude"]).to eq(40.0)
      expect(data[0]["longitude"]).to eq(116.0)
      expect(data[0]["altitude"]).to eq(10.0)
      expect(data[0]["timestamp"]).to eq("1970-01-12T13:46:40Z")
      expect(data[0]["speed"]).to eq(3.0)
      expect(data[0]["distance"]).to eq(0.0)
    end

    context "when stream has no optional arrays" do
      let(:stream) { {} }

      it "writes with nil values" do
        xz.send(:write_std, pts, stream, "test789")
        data = JSON.parse(File.read("data/std/xingzhe/test789.json"))
        expect(data[0]["altitude"]).to be_nil
        expect(data[0]["timestamp"]).to be_nil
        expect(data[0]["speed"]).to be_nil
        expect(data[0]["distance"]).to be_nil
      end
    end
  end
end

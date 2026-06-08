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

      context "and detail api returns segments_km" do
        let(:detail_data) do
          { "segments_km" => [
            { "latitude" => 40.0, "longitude" => 116.0 },
            { "latitude" => 40.001, "longitude" => 116.002 },
            { "latitude" => 40.003, "longitude" => 116.005 }
          ] }
        end

        before do
          allow(xz).to receive(:fetch_activity_detail).with(4001).and_return(detail_data)
        end

        it "generates summary_polyline from segments_km" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).not_to be_nil
          expect(row[:summary_polyline]).not_to be_empty

          decoded = Workouts::Geo::Polyline.decode(row[:summary_polyline])
          expect(decoded.size).to eq(3)
          expect(decoded[0][0]).to be_within(1e-5).of(40.0)
          expect(decoded[0][1]).to be_within(1e-5).of(116.0)
          expect(decoded[2][0]).to be_within(1e-5).of(40.003)
          expect(decoded[2][1]).to be_within(1e-5).of(116.005)
        end
      end

      context "and detail api returns without segments_km" do
        before do
          allow(xz).to receive(:fetch_activity_detail).with(4001).and_return({})
        end

        it "inserts without summary_polyline" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).to be_nil
        end
      end

      context "and detail api fails" do
        before do
          allow(xz).to receive(:fetch_activity_detail).with(4001).and_return(nil)
        end

        it "inserts without summary_polyline" do
          xz.call
          row = db[:activities].first
          expect(row[:summary_polyline]).to be_nil
        end
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
end

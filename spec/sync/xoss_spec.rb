RSpec.describe Workouts::Sync::XOSS do
  let(:db) { create_test_db }
  let(:config) { { "email" => "test@xoss.com", "password" => "pw" } }
  subject(:xoss) { described_class.new(config:, db:, activity_filter: nil) }

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
        expect(xoss.call).to eq(0)
      end
    end

    context "when login fails" do
      before { allow(xoss).to receive(:login).and_return(false) }
      it "returns 0" do
        expect(xoss.call).to eq(0)
      end
    end

    context "with activities to sync" do
      let(:activities) do
        [{ "id" => 3001, "title" => "XOSS Ride", "sport" => 2,
           "distance" => 15000.0, "duration" => 2400,
           "start_timestamp" => 1700000000, "sub_sport" => 0 }]
      end

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
end

RSpec.describe Workouts::Sync::Keep do
  let(:db) { create_test_db }
  let(:config) { { "phone" => "13800138000", "password" => "test-pw" } }
  subject(:keep) { described_class.new(config:, db:, time_budget: nil) }
  let(:compound_id) { "userhash_9223370326790482307_rn" }

  before do
    FileUtils.mkdir_p("data/raw/keep")
  end

  after do
    FileUtils.rm_rf("data/raw/keep")
  end

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
      Float :average_speed
      Float :elevation_gain
      String :source
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      index :start_date
      index :source
      index :sport_category
    end
    d
  end

  def http_response(code, body)
    instance_double(Net::HTTPResponse, code:, body:)
  end

  def login_ok
    http_response("200", %<{"data":{"token":"test-token"}}>)
  end

  def login_fail
    http_response("401", "{}")
  end

  def stats_response(*compound_ids)
    logs = compound_ids.map { |cid| { "stats" => { "id" => cid, "isDoubtful" => false } } }
    http_response("200", JSON.generate({
      "data" => { "records" => [{ "logs" => logs }], "lastTimestamp" => 0 }
    }))
  end

  def empty_stats
    http_response("200", JSON.generate({
      "data" => { "records" => [], "lastTimestamp" => nil }
    }))
  end

  def log_response
    run_data = JSON.parse(File.read("spec/fixtures/keep/run_data.json"))
    run_data["geoPoints"] = File.read("spec/fixtures/keep/encrypted_geo.txt")
    http_response("200", JSON.generate({ "data" => run_data }))
  end

  def log_fail
    http_response("500", "{}")
  end

  describe "#call" do
    context "without credentials" do
      let(:config) { {} }

      it "returns 0" do
        expect(keep.call).to eq(0)
      end

      it "does not attempt login" do
        expect(keep).not_to receive(:login)
        keep.call
      end
    end

    context "when login fails" do
      before do
        allow(keep).to receive(:http_post).with(any_args).and_return(login_fail)
      end

      it "returns 0" do
        expect(keep.call).to eq(0)
      end
    end

    context "when no new activities" do
      before do
        allow(keep).to receive(:http_post).with(any_args).and_return(login_ok)
        empty = empty_stats
        allow(keep).to receive(:http_get).and_return(empty, empty, empty)
      end

      it "returns 0" do
        expect(keep.call).to eq(0)
      end

      it "sets authorization header after login" do
        keep.call
        expect(keep.instance_variable_get(:@headers)["Authorization"]).to eq("Bearer test-token")
      end
    end

    context "with activities to sync" do
      before do
        allow(keep).to receive(:http_post).with(any_args).and_return(login_ok)
        empty = empty_stats
        allow(keep).to receive(:http_get).and_return(
          stats_response(compound_id),  # fetch_run_ids(running)
          log_response,                  # sync_single_run_with_raw
          empty,                         # fetch_run_ids(hiking)
          empty                          # fetch_run_ids(cycling)
        )
      end

      it "syncs one activity" do
        count = keep.call
        expect(count).to eq(1)
      end

      it "inserts activity into database" do
        keep.call
        expect(db[:activities].count).to eq(1)
        row = db[:activities].first
        expect(row[:run_id]).to eq("keep_9223370326790482307")
        expect(row[:source]).to eq("keep")
        expect(row[:sport_category]).to eq("run")
      end

      it "preserves raw file" do
        keep.call
        path = "data/raw/keep/9223370326790482307.json"
        expect(File.exist?(path)).to be true
        content = JSON.parse(File.read(path))
        expect(content).to be_an(Array)
      end
    end

    context "when activity already in DB and raw file exists" do
      before do
        db[:activities].insert(run_id: "keep_9223370326790482307", source: "keep")
        File.write("data/raw/keep/9223370326790482307.json", "[]")
        allow(keep).to receive(:http_post).with(any_args).and_return(login_ok)
        empty = empty_stats
        allow(keep).to receive(:http_get).and_return(
          stats_response(compound_id),  # fetch_run_ids(running)
          empty,                         # fetch_run_ids(hiking)
          empty                          # fetch_run_ids(cycling)
        )
      end

      it "skips already synced activity" do
        expect(keep.call).to eq(0)
      end
    end
  end

  describe "#sync_single_run_with_raw" do
    before do
      allow(keep).to receive(:http_get).and_return(log_response)
    end

    it "returns true on success" do
      result = keep.send(:sync_single_run_with_raw, compound_id, "running")
      expect(result).to be true
    end

    it "writes raw file" do
      keep.send(:sync_single_run_with_raw, compound_id, "running")
      path = "data/raw/keep/9223370326790482307.json"
      expect(File.exist?(path)).to be true
    end

    it "upserts activity into DB" do
      keep.send(:sync_single_run_with_raw, compound_id, "running")
      expect(db[:activities].count).to eq(1)
    end

    context "when HTTP fails" do
      before do
        allow(keep).to receive(:http_get).and_return(log_fail)
      end

      it "returns false" do
        expect(keep.send(:sync_single_run_with_raw, compound_id, "running")).to be false
      end
    end
  end

  describe "#existing_run_ids" do
    before do
      db[:activities].insert(run_id: "keep_111", source: "keep")
      db[:activities].insert(run_id: "keep_222", source: "keep")
    end

    it "returns all keep run_ids" do
      ids = keep.send(:existing_run_ids)
      expect(ids).to contain_exactly("keep_111", "keep_222")
    end
  end
end

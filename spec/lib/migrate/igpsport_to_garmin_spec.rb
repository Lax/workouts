RSpec.describe Workouts::Migrate::IGPSportToGarmin do
  let(:db) do
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

  let(:config) { {} }

  subject(:migrator) do
    described_class.new(db: db, config: config, dry: false)
  end

  def insert_igpsport_activity(overrides = {})
    now = Time.now.utc
    defaults = {
      run_id: "igpsport_12345", name: "Test Ride", distance: 5000,
      moving_time: 1500, sport_category: "ride", sport_type: "ride",
      start_date: "2025-06-01 08:00:00", start_date_local: "2025-06-01 16:00:00",
      source: "igpsport", created_at: now, updated_at: now,
      summary_polyline: nil
    }
    db[:activities].insert(defaults.merge(overrides))
  end

  describe "#load_igpsport_activities" do
    it "returns empty when no iGPSPORT activities exist" do
      expect(migrator.send(:load_igpsport_activities)).to eq([])
    end

    it "returns only iGPSPORT-sourced activities" do
      insert_igpsport_activity
      db[:activities].insert(
        run_id: "strava_1", name: "Strava Run", distance: 5000,
        moving_time: 1500, sport_category: "run",
        start_date: "2025-06-01 08:00:00",
        source: "strava", created_at: Time.now.utc, updated_at: Time.now.utc
      )
      activities = migrator.send(:load_igpsport_activities)
      expect(activities.size).to eq(1)
      expect(activities.first[:run_id]).to eq("igpsport_12345")
    end

    it "filters by --since date" do
      m = described_class.new(db: db, config: config, since: "2025-07-01")
      insert_igpsport_activity(run_id: "igpsport_old", start_date: "2025-06-01 08:00:00")
      insert_igpsport_activity(run_id: "igpsport_new", start_date: "2025-08-01 08:00:00")
      activities = m.send(:load_igpsport_activities)
      expect(activities.size).to eq(1)
      expect(activities.first[:run_id]).to eq("igpsport_new")
    end

    it "limits by --limit" do
      m = described_class.new(db: db, config: config, limit: 1)
      insert_igpsport_activity(run_id: "igpsport_a", start_date: "2025-08-01 08:00:00")
      insert_igpsport_activity(run_id: "igpsport_b", start_date: "2025-08-02 08:00:00")
      activities = m.send(:load_igpsport_activities)
      expect(activities.size).to eq(1)
    end

    it "ignores limit of 0" do
      m = described_class.new(db: db, config: config, limit: 0)
      insert_igpsport_activity(run_id: "igpsport_a", start_date: "2025-08-01 08:00:00")
      insert_igpsport_activity(run_id: "igpsport_b", start_date: "2025-08-02 08:00:00")
      activities = m.send(:load_igpsport_activities)
      expect(activities.size).to eq(2)
    end
  end

  describe "#dry_run" do
    it "prints activities and returns count" do
      insert_igpsport_activity
      activities = migrator.send(:load_igpsport_activities)
      expect { migrator.send(:dry_run, activities) }.to output(/igpsport_12345/).to_stdout
      expect(migrator.send(:dry_run, activities)).to eq(1)
    end
  end

  describe "L1 dedup — upload_map" do
    let(:tmpdir) { Dir.mktmpdir("igp2garmin_spec") }
    let(:map_dir) { File.join(tmpdir, "igpsport_to_garmin") }
    let(:map_path) { File.join(map_dir, "uploads.json") }

    before do
      allow(migrator).to receive(:upload_map_dir).and_return(map_dir)
      allow(migrator).to receive(:upload_map_path).and_return(map_path)
      allow(migrator).to receive(:authenticate).and_return(false)
    end

    after do
      FileUtils.remove_entry(tmpdir)
    end

    it "returns empty map when file missing" do
      map = migrator.send(:load_upload_map)
      expect(map["uploads"]).to eq({})
    end

    it "saves and loads upload map" do
      map = {"uploads" => {"igpsport_12345" => {"garmin_activity_id" => "987"}}}
      migrator.send(:save_upload_map, map)
      loaded = migrator.send(:load_upload_map)
      expect(loaded["uploads"]["igpsport_12345"]["garmin_activity_id"]).to eq("987")
    end

    it "skips already uploaded activities in call" do
      insert_igpsport_activity
      FileUtils.mkdir_p(map_dir)
      File.write(map_path, JSON.generate({
        "uploads" => {"igpsport_12345" => {"garmin_activity_id" => "987"}}
      }))
      allow(migrator).to receive(:authenticate).and_call_original
      expect(migrator.call).to eq(0)
    end
  end

  describe "L2 dedup — name suffix match" do
    it "finds match by [iGPSPORT] suffix" do
      activities = JSON.parse(load_fixture("garmin/activity_list.json"))
      result = migrator.send(:find_name_suffix_match, activities)
      expect(result).not_to be_nil
      expect(result["activityId"]).to eq(11111)
    end

    it "returns nil when no match" do
      activities = [
        {"activityName" => "Morning Run", "activityId" => 33333}
      ]
      result = migrator.send(:find_name_suffix_match, activities)
      expect(result).to be_nil
    end

    it "returns nil for empty list" do
      expect(migrator.send(:find_name_suffix_match, [])).to be_nil
    end
  end

  describe "#authenticate" do
    it "calls Auth::GarminToken.for_intl" do
      expect(Workouts::Auth::GarminToken).to receive(:for_intl)
        .with(config)
        .and_return(access_token: "at", domain: "garmin.com")
      expect(migrator.send(:authenticate)).to be true
    end

    it "returns false when token fetch fails" do
      expect(Workouts::Auth::GarminToken).to receive(:for_intl).and_return(nil)
      expect(migrator.send(:authenticate)).to be false
    end

    it "sets @access_token and @domain" do
      expect(Workouts::Auth::GarminToken).to receive(:for_intl)
        .and_return(access_token: "my_token", domain: "garmin.com")
      migrator.send(:authenticate)
      expect(migrator.instance_variable_get(:@access_token)).to eq("my_token")
      expect(migrator.instance_variable_get(:@domain)).to eq("garmin.com")
    end
  end

  describe "#authenticate (CN)" do
    it "calls Auth::GarminToken.for_cn" do
      m = Workouts::Migrate::IGPSportToGarminCN.new(db: db, config: config)
      expect(Workouts::Auth::GarminToken).to receive(:for_cn)
        .with(config)
        .and_return(access_token: "cn_at", domain: "garmin.cn")
      expect(m.send(:authenticate)).to be true
    end
  end

  describe "#build_gpx" do
    let(:act) do
      {run_id: "igpsport_12345", name: "Test Ride", start_date: "2025-06-01 08:00:00",
       sport_category: "ride"}
    end
    let(:l2) { JSON.parse(load_fixture("igpsport/sample_l2.json")) }

    it "builds valid GPX XML" do
      xml = migrator.send(:build_gpx, act, l2)
      doc = Nokogiri::XML(xml)
      expect(doc.errors).to be_empty
      expect(doc.at_xpath("//xmlns:gpx")).not_to be_nil
    end

    it "includes [iGPSPORT] suffix in name" do
      xml = migrator.send(:build_gpx, act, l2)
      expect(xml).to include("Test Ride [iGPSPORT]")
    end

    it "includes src element with run_id" do
      xml = migrator.send(:build_gpx, act, l2)
      expect(xml).to include("<src>igpsport_12345</src>")
    end

    it "includes desc with source info" do
      xml = migrator.send(:build_gpx, act, l2)
      expect(xml).to include("Source: igpsport_12345")
    end

    it "includes link with run_id" do
      xml = migrator.send(:build_gpx, act, l2)
      expect(xml).to include("igpsport.com/activity/igpsport_12345")
    end

    it "preserves trackpoint fields" do
      xml = migrator.send(:build_gpx, act, l2)
      expect(xml).to include("<gpxtpx:hr>145</gpxtpx:hr>")
      expect(xml).to include("<gpxtpx:cad>85</gpxtpx:cad>")
      expect(xml).to include("<gpxtpx:watts>200</gpxtpx:watts>")
      expect(xml).to include("<gpxtpx:temp>25</gpxtpx:temp>")
    end

    it "includes sport type in GPX" do
      xml = migrator.send(:build_gpx, act, l2)
      expect(xml).to include("<type>cycling</type>")
    end

    it "filters out nil lat/lng points" do
      bad_l2 = l2.dup << {"altitude" => 10}
      xml = migrator.send(:build_gpx, act, bad_l2)
      doc = Nokogiri::XML(xml)
      trkpts = doc.xpath("//xmlns:trkpt")
      expect(trkpts.size).to eq(3)
    end
  end

  describe "#parse_upload_response" do
    it "returns garmin_activity_id on success" do
      resp = instance_double(Faraday::Response, status: 200,
        body: load_fixture("garmin/upload_success.json"))
      result = migrator.send(:parse_upload_response, resp)
      expect(result["garmin_activity_id"]).to eq("987654321")
      expect(result["format"]).to eq("fit")
    end

    it "returns nil on failure response" do
      resp = instance_double(Faraday::Response, status: 200,
        body: load_fixture("garmin/upload_failure.json"))
      expect(migrator.send(:parse_upload_response, resp)).to be_nil
    end

    it "returns nil on non-200 status" do
      resp = instance_double(Faraday::Response, status: 500)
      expect(migrator.send(:parse_upload_response, resp)).to be_nil
    end
  end

  describe "#raw_igpsport_path" do
    it "builds correct path" do
      expect(migrator.send(:raw_igpsport_path, "12345"))
        .to eq("data/raw/igpsport/12345.fit")
    end
  end

  describe "#upload_map_dir" do
    it "uses igpsport_to_garmin for intl" do
      expect(migrator.send(:upload_map_dir)).to eq("data/migrate/igpsport_to_garmin")
    end

    it "uses igpsport_to_garmin_cn for cn" do
      m = Workouts::Migrate::IGPSportToGarminCN.new(db: db, config: {})
      expect(m.send(:upload_map_dir)).to eq("data/migrate/igpsport_to_garmin_cn")
    end
  end

  describe "#esc" do
    it "escapes XML special chars" do
      result = migrator.send(:esc, 'A&B <C> "D\'E"')
      expect(result).to eq("A&amp;B &lt;C&gt; &quot;D&apos;E&quot;")
    end
  end
end

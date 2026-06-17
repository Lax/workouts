RSpec.describe Workouts::Sync::Garmin do
  let(:db) do
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

  let(:tmpdir) { Dir.mktmpdir }

  def di_token_path(adapter)
    adapter.send(:di_token_path)
  end

  def di_token_json(expires_at: Time.now.to_i + 3600, access_token: "di_test_at", refresh_token: "di_test_rt")
    {
      "access_token" => access_token,
      "refresh_token" => refresh_token,
      "expires_in" => 64800,
      "expires_at" => expires_at,
      "refresh_token_expires_in" => 2592000,
      "refresh_token_expires_at" => expires_at + 2592000,
      "scope" => "test",
      "token_type" => "Bearer"
    }
  end

  def write_di_token(adapter, token = nil)
    t = token || di_token_json
    path = di_token_path(adapter)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(t))
  end

  def stub_di_adapter(config_overrides: {})
    config = { "email" => "test@gb.com", "password" => "pw", "di_token_path" => File.join(tmpdir, "garmin_tokens.json") }.merge(config_overrides)
    Class.new(described_class) do
      def fetch_oauth_consumer; {}; end
      def strategy_a_login; nil; end
      def strategy_b_login; nil; end
      def verify_access_token; true; end
      def api_get(path)
        [{ "activityId" => 1 }] if path.include?("search/activities")
      end
    end.new(config:, db:, activity_filter: nil)
  end

  after { FileUtils.remove_entry(tmpdir) }

  describe "#authenticate (dispatcher)" do
    it "routes to authenticate_di for garmin.com" do
      adapter = stub_di_adapter
      write_di_token(adapter)
      expect(adapter).to receive(:authenticate_di).and_call_original
      expect(adapter.authenticate).to be true
    end
  end

  describe "#authenticate_di" do
    context "with valid cached DI token" do
      subject(:adapter) { stub_di_adapter }

      before { write_di_token(adapter, di_token_json(expires_at: Time.now.to_i + 3600)) }

      it "returns true without refreshing" do
        expect(adapter).not_to receive(:di_refresh)
        expect(adapter.authenticate_di).to be true
      end

      it "sets access_token from cache" do
        adapter.authenticate_di
        expect(adapter.instance_variable_get(:@access_token)["access_token"]).to eq("di_test_at")
      end
    end

    context "with expired DI token that can be refreshed" do
      subject(:adapter) { stub_di_adapter }

      before do
        write_di_token(adapter, di_token_json(expires_at: Time.now.to_i - 3600))
        allow(adapter).to receive(:di_refresh).and_return(true)
      end

      it "calls di_refresh and returns true" do
        expect(adapter).to receive(:di_refresh).and_return(true)
        expect(adapter.authenticate_di).to be true
      end
    end

    context "with expired DI token and refresh fails" do
      subject(:adapter) { stub_di_adapter }

      before do
        write_di_token(adapter, di_token_json(expires_at: Time.now.to_i - 3600))
        allow(adapter).to receive(:di_refresh).and_raise(Workouts::AuthError, "refresh failed")
      end

      it "removes stale tokens and returns false (no strategy)" do
        expect(adapter).to receive(:remove_stale_di_tokens).and_call_original
        expect(adapter.authenticate_di).to be false
      end

      it "deletes the stale token file" do
        path = di_token_path(adapter)
        expect(File.exist?(path)).to be true
        adapter.authenticate_di
        expect(File.exist?(path)).to be false
      end
    end

    context "without cached token and without credentials" do
      subject(:adapter) { stub_di_adapter(config_overrides: { "email" => "", "password" => "" }) }

      it "returns false" do
        expect(adapter.authenticate_di).to be false
      end
    end

    context "without cached token, strategy A succeeds" do
      subject(:adapter) { stub_di_adapter }

      before do
        token = di_token_json
        allow(adapter).to receive(:strategy_a_login).and_return(token)
      end

      it "saves token and returns true" do
        expect(adapter).to receive(:save_di_tokens).and_call_original
        expect(adapter).to receive(:verify_access_token).and_return(true)
        expect(adapter.authenticate_di).to be true
      end
    end

    context "without cached token, strategy A fails but B succeeds" do
      subject(:adapter) { stub_di_adapter }

      before do
        token = di_token_json
        allow(adapter).to receive(:strategy_a_login).and_return(nil)
        allow(adapter).to receive(:strategy_b_login).and_return(token)
      end

      it "saves token and returns true" do
        expect(adapter).to receive(:save_di_tokens).and_call_original
        expect(adapter).to receive(:verify_access_token).and_return(true)
        expect(adapter.authenticate_di).to be true
      end
    end

    context "without cached token, all strategies fail" do
      subject(:adapter) { stub_di_adapter }

      before do
        allow(adapter).to receive(:strategy_a_login).and_return(nil)
        allow(adapter).to receive(:strategy_b_login).and_return(nil)
      end

      it "returns false" do
        expect(adapter.authenticate_di).to be false
      end
    end
  end

  describe "#load_di_tokens" do
    subject(:adapter) { stub_di_adapter }

    it "returns true when token file exists" do
      write_di_token(adapter)
      expect(adapter.send(:load_di_tokens)).to be true
      expect(adapter.instance_variable_get(:@access_token)["access_token"]).to eq("di_test_at")
    end

    it "returns false when token file does not exist" do
      expect(adapter.send(:load_di_tokens)).to be false
    end
  end

  describe "#save_di_tokens" do
    subject(:adapter) { stub_di_adapter }

    it "writes token to file" do
      adapter.instance_variable_set(:@access_token, di_token_json)
      adapter.send(:save_di_tokens)
      expect(File.exist?(di_token_path(adapter))).to be true
      loaded = JSON.parse(File.read(di_token_path(adapter)))
      expect(loaded["access_token"]).to eq("di_test_at")
    end

    it "does nothing when access_token is nil" do
      adapter.send(:save_di_tokens)
      expect(File.exist?(di_token_path(adapter))).to be false
    end

    it "does nothing when access_token has no access_token key" do
      adapter.instance_variable_set(:@access_token, {})
      adapter.send(:save_di_tokens)
      expect(File.exist?(di_token_path(adapter))).to be false
    end
  end

  describe "#remove_stale_di_tokens" do
    subject(:adapter) { stub_di_adapter }

    it "deletes token file when it exists" do
      write_di_token(adapter)
      adapter.send(:remove_stale_di_tokens)
      expect(File.exist?(di_token_path(adapter))).to be false
    end

    it "does not raise when file does not exist" do
      expect { adapter.send(:remove_stale_di_tokens) }.not_to raise_error
    end
  end

  describe "#di_refresh" do
    subject(:adapter) { stub_di_adapter }

    before do
      adapter.instance_variable_set(:@access_token, di_token_json(
        expires_at: Time.now.to_i - 3600,
        refresh_token: "my_refresh_token"
      ))
      # Allow save_di_tokens in di_refresh
      allow(adapter).to receive(:save_di_tokens)
    end

    it "returns false when access_token has no refresh_token" do
      adapter.instance_variable_set(:@access_token, { "access_token" => "x" })
      expect(adapter.send(:di_refresh)).to be false
    end

    it "posts to di auth endpoint and updates access_token" do
      new_token = { "access_token" => "new_di_at", "refresh_token" => "new_di_rt", "expires_in" => 64800 }
      resp = double("resp", code: "200", body: JSON.generate(new_token))
      expect(adapter).to receive(:send_http).and_return(resp)
      expect(adapter).to receive(:save_di_tokens)
      expect(adapter.send(:di_refresh)).to be true
      expect(adapter.instance_variable_get(:@access_token)["access_token"]).to eq("new_di_at")
    end

    it "raises AuthError on non-200 response" do
      resp = double("resp", code: "401")
      expect(adapter).to receive(:send_http).and_return(resp)
      expect { adapter.send(:di_refresh) }.to raise_error(Workouts::AuthError, /DI refresh error/)
    end
  end

  describe "#strategy_a_login" do
    let(:adapter) do
      # adapter without strategy_a_login override (tests real subprocess call)
      config = { "email" => "test@gb.com", "password" => "pw", "di_token_path" => File.join(tmpdir, "garmin_tokens.json") }
      Class.new(described_class) do
        def fetch_oauth_consumer; {}; end
        def strategy_b_login; nil; end
      end.new(config:, db:, activity_filter: nil)
    end

    it "returns nil when script file does not exist" do
      expect(adapter.send(:strategy_a_login)).to be nil
    end

    it "calls python3 subprocess with env vars and parses JSON on success" do
      token = di_token_json
      stdout = JSON.generate(token)
      status = double("Process::Status", success?: true)

      # Script path as computed by the library (project_root/scripts/garmin_auth.py)
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).with(
        hash_including("GARMIN_EMAIL" => "test@gb.com", "GARMIN_PASSWORD" => "pw", "GARMIN_DOMAIN" => "garmin.com"),
        "python3", resolved
      ).and_return([stdout, "", status])

      result = adapter.send(:strategy_a_login)
      expect(result["access_token"]).to eq("di_test_at")
      expect(result["refresh_token"]).to eq("di_test_rt")
    end

    it "logs stderr on success" do
      token = di_token_json
      stdout = JSON.generate(token)
      status = double("Process::Status", success?: true)
      # Script path as computed by the library (project_root/scripts/garmin_auth.py)
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      expect(Open3).to receive(:capture3).and_return([stdout, "debug info", status])

      expect { adapter.send(:strategy_a_login) }.to output(/debug info/).to_stderr
    end

    it "returns nil on subprocess failure" do
      status = double("Process::Status", success?: false)
      # Script path as computed by the library (project_root/scripts/garmin_auth.py)
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).and_return(["", "error msg", status])

      expect(adapter.send(:strategy_a_login)).to be nil
    end

    it "returns nil on JSON parse error" do
      status = double("Process::Status", success?: true)
      # Script path as computed by the library (project_root/scripts/garmin_auth.py)
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).and_return(["not json", "", status])

      expect(adapter.send(:strategy_a_login)).to be nil
    end

    it "returns nil on subprocess exception" do
      # Script path as computed by the library (project_root/scripts/garmin_auth.py)
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "python3 not found")

      expect(adapter.send(:strategy_a_login)).to be nil
    end
  end

  describe "#strategy_b_login" do
    let(:adapter) do
      config = { "email" => "test@gb.com", "password" => "pw", "di_token_path" => File.join(tmpdir, "garmin_tokens.json") }
      Class.new(described_class) do
        def fetch_oauth_consumer; {}; end
        def strategy_a_login; nil; end
      end.new(config:, db:, activity_filter: nil)
    end

    it "returns nil when script file does not exist" do
      expect(adapter.send(:strategy_b_login)).to be nil
    end

    it "calls python3 subprocess with env vars and parses JSON on success" do
      token = di_token_json
      stdout = JSON.generate(token)
      status = double("Process::Status", success?: true)
      resolved = File.expand_path("scripts/garmin_auth_playwright.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).with(
        hash_including("GARMIN_EMAIL" => "test@gb.com", "GARMIN_PASSWORD" => "pw", "GARMIN_DOMAIN" => "garmin.com"),
        "python3", resolved
      ).and_return([stdout, "", status])

      result = adapter.send(:strategy_b_login)
      expect(result["access_token"]).to eq("di_test_at")
    end

    it "returns nil on subprocess failure" do
      status = double("Process::Status", success?: false)
      resolved = File.expand_path("scripts/garmin_auth_playwright.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).and_return(["", "error", status])

      expect(adapter.send(:strategy_b_login)).to be nil
    end

    it "returns nil on subprocess exception" do
      resolved = File.expand_path("scripts/garmin_auth_playwright.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "python3 not found")

      expect(adapter.send(:strategy_b_login)).to be nil
    end
  end

  describe "#call" do
    context "with email+password set" do
      subject(:adapter) { stub_di_adapter }

      before do
        write_di_token(adapter)
        allow(adapter).to receive(:sync_activities).and_return(5)
      end

      it "calls authenticate and sync_activities" do
        expect(adapter.call).to eq(5)
      end
    end

    context "without credentials but with cached token" do
      subject(:adapter) { stub_di_adapter(config_overrides: { "email" => "", "password" => "" }) }

      before do
        write_di_token(adapter, di_token_json(expires_at: Time.now.to_i + 3600))
        allow(adapter).to receive(:sync_activities).and_return(3)
      end

      it "calls sync_activities" do
        expect(adapter.call).to eq(3)
      end
    end

    context "without credentials and without cached token" do
      subject(:adapter) { stub_di_adapter(config_overrides: { "email" => "", "password" => "" }) }

      it "returns 0" do
        expect(adapter.call).to eq(0)
      end
    end

    context "when authenticate fails" do
      subject(:adapter) { stub_di_adapter }

      before do
        allow(adapter).to receive(:authenticate_di).and_return(false)
      end

      it "returns 0" do
        expect(adapter.call).to eq(0)
      end
    end
  end
end

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

  let(:tmpdir) { Dir.mktmpdir }

  def token_json(expires_at: Time.now.to_i + 3600, access_token: "di_test_at", refresh_token: "di_test_rt")
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

  def write_token(adapter, token = nil)
    t = token || token_json
    path = adapter.send(:token_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(t))
  end

  def stub_adapter(config_overrides: {})
    config = { "email" => "test@gb.com", "password" => "pw", "token_path" => File.join(tmpdir, "garmin_tokens.json") }.merge(config_overrides)
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

  describe "#authenticate" do
    context "with valid cached token" do
      subject(:adapter) { stub_adapter }

      before { write_token(adapter, token_json(expires_at: Time.now.to_i + 3600)) }

      it "returns true without refreshing" do
        expect(adapter).not_to receive(:refresh_token)
        expect(adapter.authenticate).to be true
      end

      it "sets access_token from cache" do
        adapter.authenticate
        expect(adapter.instance_variable_get(:@access_token)["access_token"]).to eq("di_test_at")
      end
    end

    context "with expired token that can be refreshed" do
      subject(:adapter) { stub_adapter }

      before do
        write_token(adapter, token_json(expires_at: Time.now.to_i - 3600))
        allow(adapter).to receive(:refresh_token).and_return(true)
      end

      it "calls refresh_token and returns true" do
        expect(adapter).to receive(:refresh_token).and_return(true)
        expect(adapter.authenticate).to be true
      end
    end

    context "with expired token and refresh fails" do
      subject(:adapter) { stub_adapter }

      before do
        write_token(adapter, token_json(expires_at: Time.now.to_i - 3600))
        allow(adapter).to receive(:refresh_token).and_raise(Workouts::AuthError, "refresh failed")
      end

      it "removes stale tokens and returns false (no strategy)" do
        expect(adapter).to receive(:remove_stale_tokens).and_call_original
        expect(adapter.authenticate).to be false
      end

      it "deletes the stale token file" do
        path = adapter.send(:token_path)
        expect(File.exist?(path)).to be true
        adapter.authenticate
        expect(File.exist?(path)).to be false
      end
    end

    context "without cached token and without credentials" do
      subject(:adapter) { stub_adapter(config_overrides: { "auth_seed" => "" }) }

      it "returns false" do
        expect(adapter.authenticate).to be false
      end
    end

    context "without cache, with valid seed token" do
      subject(:adapter) do
        seed = Base64.strict_encode64(JSON.generate(token_json(expires_at: Time.now.to_i + 3600)))
        stub_adapter(config_overrides: {"auth_seed" => seed})
      end

      it "loads seed token and returns true" do
        expect(adapter).to receive(:load_auth_seed).and_call_original
        expect(adapter.authenticate).to be true
      end

      it "saves seed token to cache" do
        adapter.authenticate
        expect(File.exist?(adapter.send(:token_path))).to be true
      end
    end

    context "without cache, with expired seed token (refreshable)" do
      subject(:adapter) do
        seed = Base64.strict_encode64(JSON.generate(token_json(
          expires_at: Time.now.to_i - 3600,
          refresh_token: "my_refresh_token"
        )))
        stub_adapter(config_overrides: {"auth_seed" => seed})
      end

      before do
        allow(adapter).to receive(:refresh_token).and_return(true)
      end

      it "falls through to refresh_token and returns true" do
        expect(adapter).to receive(:refresh_token).and_return(true)
        expect(adapter.authenticate).to be true
      end
    end
  end

  describe "#load_tokens" do
    subject(:adapter) { stub_adapter }

    it "returns true when token file exists" do
      write_token(adapter)
      expect(adapter.send(:load_tokens)).to be true
      expect(adapter.instance_variable_get(:@access_token)["access_token"]).to eq("di_test_at")
    end

    it "returns false when token file does not exist" do
      expect(adapter.send(:load_tokens)).to be false
    end
  end

  describe "#save_tokens" do
    subject(:adapter) { stub_adapter }

    it "writes token to file" do
      adapter.instance_variable_set(:@access_token, token_json)
      adapter.send(:save_tokens)
      expect(File.exist?(adapter.send(:token_path))).to be true
      loaded = JSON.parse(File.read(adapter.send(:token_path)))
      expect(loaded["access_token"]).to eq("di_test_at")
    end

    it "does nothing when access_token is nil" do
      adapter.send(:save_tokens)
      expect(File.exist?(adapter.send(:token_path))).to be false
    end

    it "does nothing when access_token has no access_token key" do
      adapter.instance_variable_set(:@access_token, {})
      adapter.send(:save_tokens)
      expect(File.exist?(adapter.send(:token_path))).to be false
    end
  end

  describe "#remove_stale_tokens" do
    subject(:adapter) { stub_adapter }

    it "deletes token file when it exists" do
      write_token(adapter)
      adapter.send(:remove_stale_tokens)
      expect(File.exist?(adapter.send(:token_path))).to be false
    end

    it "does not raise when file does not exist" do
      expect { adapter.send(:remove_stale_tokens) }.not_to raise_error
    end
  end

  describe "#load_auth_seed" do
    it "decodes Base64 auth_seed from config and saves to cache" do
      seed = Base64.strict_encode64(JSON.generate(token_json))
      adapter = stub_adapter(config_overrides: {"auth_seed" => seed})
      expect(adapter.send(:load_auth_seed)).to be true
      expect(adapter.instance_variable_get(:@access_token)["access_token"]).to eq("di_test_at")
      expect(File.exist?(adapter.send(:token_path))).to be true
    end

    it "returns false when config has no auth_seed" do
      adapter = stub_adapter
      expect(adapter.send(:load_auth_seed)).to be false
    end

    it "returns false when auth_seed is empty" do
      adapter = stub_adapter(config_overrides: {"auth_seed" => ""})
      expect(adapter.send(:load_auth_seed)).to be false
    end

    it "returns false on invalid Base64" do
      adapter = stub_adapter(config_overrides: {"auth_seed" => "!!!invalid!!!"})
      expect(adapter.send(:load_auth_seed)).to be false
    end

    it "returns false on invalid JSON" do
      adapter = stub_adapter(config_overrides: {"auth_seed" => Base64.strict_encode64("not json")})
      expect(adapter.send(:load_auth_seed)).to be false
    end
  end

  describe "#refresh_token" do
    subject(:adapter) { stub_adapter }

    before do
      adapter.instance_variable_set(:@access_token, token_json(
        expires_at: Time.now.to_i - 3600,
        refresh_token: "my_refresh_token"
      ))
      allow(adapter).to receive(:save_tokens)
    end

    it "returns false when access_token has no refresh_token" do
      adapter.instance_variable_set(:@access_token, { "access_token" => "x" })
      expect(adapter.send(:refresh_token)).to be false
    end

    it "includes Basic auth header with client_id" do
      new_token = { "access_token" => "new_di_at", "refresh_token" => "new_di_rt", "expires_in" => 64800 }
      resp = double("resp", code: "200", body: JSON.generate(new_token))
      expect(adapter).to receive(:save_tokens)
      expect(adapter).to receive(:send_http) do |_uri, req|
        auth = req["Authorization"]
        expect(auth).to match(/^Basic /)
        expect(req["Cache-Control"]).to eq("no-cache")
        expect(req["User-Agent"]).to eq("GCM-Android-5.23")
        body = URI.decode_www_form(req.body).to_h
        expect(body["client_id"]).to match(/GARMIN_CONNECT/)
        resp
      end
      expect(adapter.send(:refresh_token)).to be true
    end

    it "raises AuthError on non-200 response" do
      resp = double("resp", code: "401")
      expect(adapter).to receive(:send_http).and_return(resp)
      expect { adapter.send(:refresh_token) }.to raise_error(Workouts::AuthError, /DI refresh error/)
    end
  end

  describe "#strategy_a_login" do
    let(:adapter) do
      config = { "email" => "test@gb.com", "password" => "pw", "token_path" => File.join(tmpdir, "garmin_tokens.json") }
      Class.new(described_class) do
        def fetch_oauth_consumer; {}; end
        def strategy_b_login; nil; end
      end.new(config:, db:, activity_filter: nil)
    end

    it "returns nil when script file does not exist" do
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(false)
      expect(adapter.send(:strategy_a_login)).to be nil
    end

    it "calls python3 subprocess with env vars and parses JSON on success" do
      token = token_json
      stdout = JSON.generate(token)
      status = double("Process::Status", success?: true)
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).with(
        hash_including("SYNC__GARMIN__EMAIL" => "test@gb.com", "SYNC__GARMIN__PASSWORD" => "pw", "SYNC__GARMIN__DOMAIN" => "garmin.com"),
        "python3", resolved
      ).and_return([stdout, "", status])

      result = adapter.send(:strategy_a_login)
      expect(result["access_token"]).to eq("di_test_at")
      expect(result["refresh_token"]).to eq("di_test_rt")
    end

    it "returns nil on subprocess failure" do
      status = double("Process::Status", success?: false)
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).and_return(["", "error msg", status])

      expect(adapter.send(:strategy_a_login)).to be nil
    end

    it "returns nil on subprocess exception" do
      resolved = File.expand_path("scripts/garmin_auth.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "python3 not found")

      expect(adapter.send(:strategy_a_login)).to be nil
    end
  end

  describe "#strategy_b_login" do
    let(:adapter) do
      config = { "email" => "test@gb.com", "password" => "pw", "token_path" => File.join(tmpdir, "garmin_tokens.json") }
      Class.new(described_class) do
        def fetch_oauth_consumer; {}; end
        def strategy_a_login; nil; end
      end.new(config:, db:, activity_filter: nil)
    end

    it "returns nil when script file does not exist" do
      resolved = File.expand_path("scripts/garmin_auth_playwright.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(false)
      expect(adapter.send(:strategy_b_login)).to be nil
    end

    it "calls python3 subprocess with env vars and parses JSON on success" do
      token = token_json
      stdout = JSON.generate(token)
      status = double("Process::Status", success?: true)
      resolved = File.expand_path("scripts/garmin_auth_playwright.py", Dir.pwd)
      allow(File).to receive(:exist?).with(resolved).and_return(true)
      allow(Open3).to receive(:capture3).with(
        hash_including("SYNC__GARMIN__EMAIL" => "test@gb.com", "SYNC__GARMIN__PASSWORD" => "pw", "SYNC__GARMIN__DOMAIN" => "garmin.com"),
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
    context "with auth_seed set" do
      subject(:adapter) { stub_adapter(config_overrides: { "auth_seed" => Base64.strict_encode64(JSON.generate(token_json)) }) }

      before do
        allow(adapter).to receive(:sync_activities).and_return(5)
      end

      it "calls authenticate and sync_activities" do
        expect(adapter.call).to eq(5)
      end
    end

    context "without auth_seed but with cached token" do
      subject(:adapter) { stub_adapter(config_overrides: { "auth_seed" => "" }) }

      before do
        write_token(adapter, token_json(expires_at: Time.now.to_i + 3600))
        allow(adapter).to receive(:sync_activities).and_return(3)
      end

      it "calls sync_activities" do
        expect(adapter.call).to eq(3)
      end
    end

    context "without auth_seed and without cached token" do
      subject(:adapter) { stub_adapter(config_overrides: { "auth_seed" => "" }) }

      it "returns 0" do
        expect(adapter.call).to eq(0)
      end
    end

    context "when authenticate fails" do
      subject(:adapter) { stub_adapter(config_overrides: { "auth_seed" => Base64.strict_encode64(JSON.generate(token_json)) }) }

      before do
        allow(adapter).to receive(:authenticate).and_return(false)
      end

      it "returns 0" do
        expect(adapter.call).to eq(0)
      end
    end
  end
end

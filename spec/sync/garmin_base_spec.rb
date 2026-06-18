RSpec.describe Workouts::Sync::GarminBase do
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

  def stub_adapter(config_overrides: {})
    config = { "email" => "test@gb.com", "password" => "pw" }.merge(config_overrides)
    Class.new(described_class) do
      def fetch_oauth_consumer; {}; end
      def sso_login; "test_ticket"; end
      def fetch_oauth1_token(...); OpenStruct.new(oauth_token: "new_o1", oauth_token_secret: "new_o1s", mfa_token: nil, domain: @domain); end
      def exchange_oauth2; {"access_token" => "new_at", "refresh_token" => "new_rt", "expires_in" => 21600, "expires_at" => Time.now.to_i + 21600, "refresh_token_expires_in" => 7776000, "refresh_token_expires_at" => Time.now.to_i + 7776000}; end
    end.new(config:, db:, activity_filter: nil)
  end

  def build_secret(domain: "garmin.cn", expires_at: Time.now.to_i + 3600)
    o1 = {
      "oauth_token" => "test_oauth_token",
      "oauth_token_secret" => "test_oauth_token_secret",
      "mfa_token" => nil,
      "mfa_expiration_timestamp" => nil,
      "domain" => domain
    }
    o2 = {
      "scope" => "test", "jti" => "test-jti",
      "token_type" => "Bearer",
      "access_token" => "test_access_token",
      "refresh_token" => "test_refresh_token",
      "expires_in" => 21600,
      "expires_at" => expires_at,
      "refresh_token_expires_in" => 7776000,
      "refresh_token_expires_at" => expires_at + 7776000
    }
    Base64.strict_encode64(JSON.generate([o1, o2]))
  end

  describe "#token_path" do
    subject(:adapter) { stub_adapter }

    it "uses domain-based data/cache path" do
      expect(adapter.send(:token_path)).to include("data/cache/garmin_")
    end

    it "includes domain in path" do
      adapter.instance_variable_set(:@domain, "garmin.com")
      expect(adapter.send(:token_path)).to include("garmin_com")
    end
  end

  describe "#parse_secret_string" do
    subject(:adapter) { stub_adapter }

    it "parses valid secret and sets OAuth1 + OAuth2 tokens" do
      expect(adapter.send(:parse_secret_string, build_secret)).to be true
      o1 = adapter.instance_variable_get(:@oauth1_token)
      o2 = adapter.instance_variable_get(:@access_token)
      expect(o1.oauth_token).to eq("test_oauth_token")
      expect(o1.oauth_token_secret).to eq("test_oauth_token_secret")
      expect(o2["access_token"]).to eq("test_access_token")
    end

    it "sets domain from secret" do
      adapter.send(:parse_secret_string, build_secret(domain: "garmin.cn"))
      expect(adapter.instance_variable_get(:@domain)).to eq("garmin.cn")
    end

    it "uses @domain as fallback when secret lacks domain" do
      adapter.instance_variable_set(:@domain, "fallback.test")
      adapter.send(:parse_secret_string, build_secret(domain: nil))
      o1 = adapter.instance_variable_get(:@oauth1_token)
      expect(o1.domain).to eq("fallback.test")
    end

    it "returns false for invalid base64" do
      expect(adapter.send(:parse_secret_string, "!!!not-base64!!!")).to be false
    end

    it "returns false for invalid JSON" do
      bad = Base64.strict_encode64("not-json")
      expect(adapter.send(:parse_secret_string, bad)).to be false
    end
  end

  describe "#dump_secret" do
    subject(:adapter) { stub_adapter }

    before { adapter.send(:parse_secret_string, build_secret) }

    it "outputs base64-encoded JSON array" do
      dumped = adapter.send(:dump_secret)
      decoded = JSON.parse(Base64.strict_decode64(dumped))
      expect(decoded).to be_an(Array)
      expect(decoded.size).to eq(2)
    end

    it "round-trips parse → dump → parse same OAuth1 fields" do
      dumped = adapter.send(:dump_secret)
      fresh = stub_adapter
      fresh.send(:parse_secret_string, dumped)
      o1_orig = adapter.instance_variable_get(:@oauth1_token)
      o1_fresh = fresh.instance_variable_get(:@oauth1_token)
      expect(o1_fresh.oauth_token).to eq(o1_orig.oauth_token)
      expect(o1_fresh.oauth_token_secret).to eq(o1_orig.oauth_token_secret)
      expect(o1_fresh.domain).to eq(o1_orig.domain)
    end
  end

  describe "#verify_access_token" do
    subject(:adapter) { stub_adapter }

    before { adapter.send(:parse_secret_string, build_secret) }

    it "returns true when API call succeeds" do
      expect(adapter).to receive(:api_get).and_return([{}])
      expect(adapter.send(:verify_access_token)).to be true
    end

    it "returns false when API call fails (nil)" do
      expect(adapter).to receive(:api_get).and_return(nil)
      expect(adapter.send(:verify_access_token)).to be false
    end

    it "returns false when API raises" do
      expect(adapter).to receive(:api_get).and_raise(StandardError)
      expect(adapter.send(:verify_access_token)).to be false
    end
  end

  describe "#remove_stale_tokens" do
    subject(:adapter) { stub_adapter }
    let(:tmpdir_token) { Dir.mktmpdir }
    let(:token_file) { File.join(tmpdir_token, "tokens.json") }

    before { allow(adapter).to receive(:token_path) { token_file } }
    after { FileUtils.remove_entry(tmpdir_token) }

    it "deletes token file when it exists" do
      File.write(token_file, "{}")
      adapter.send(:remove_stale_tokens)
      expect(File.exist?(token_file)).to be false
    end

    it "does not raise when file does not exist" do
      expect { adapter.send(:remove_stale_tokens) }.not_to raise_error
    end
  end

  describe "#access_token_valid?" do
    subject(:adapter) { stub_adapter }

    it "returns false when access_token is nil" do
      expect(adapter.send(:access_token_valid?)).to be false
    end

    it "returns true when expires_at is in the future" do
      adapter.instance_variable_set(:@access_token, { "expires_at" => Time.now.to_i + 3600 })
      expect(adapter.send(:access_token_valid?)).to be true
    end

    it "returns false when expires_at is in the past" do
      adapter.instance_variable_set(:@access_token, { "expires_at" => Time.now.to_i - 60 })
      expect(adapter.send(:access_token_valid?)).to be false
    end

    it "returns true when expires_at is nil" do
      adapter.instance_variable_set(:@access_token, {})
      expect(adapter.send(:access_token_valid?)).to be true
    end
  end
end

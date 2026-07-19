RSpec.describe Workouts::Config do
  describe "default timezone (DEFAULTS)" do
    it "defaults to Asia/Shanghai in DEFAULTS" do
      expect(described_class::DEFAULTS.dig("system", "timezone")).to eq("Asia/Shanghai")
    end

    it "loads from config file when path is given" do
      Dir.mktmpdir do |tmpdir|
        config_path = File.join(tmpdir, "config.yml")
        File.write(config_path, "system:\n  timezone: America/New_York\n")
        cfg = described_class.new(config_path)
        expect(cfg.dig("system", "timezone")).to eq("America/New_York")
      end
    end

    it "can be overridden via env var" do
      orig = ENV["SYSTEM__TIMEZONE"]
      ENV["SYSTEM__TIMEZONE"] = "Europe/London"
      begin
        Dir.mktmpdir do |tmpdir|
          config_path = File.join(tmpdir, "empty.yml")
          File.write(config_path, "---\n")
          cfg = described_class.new(config_path)
          expect(cfg.dig("system", "timezone")).to eq("Europe/London")
        end
      ensure
        if orig
          ENV["SYSTEM__TIMEZONE"] = orig
        else
          ENV.delete("SYSTEM__TIMEZONE")
        end
      end
    end
  end

  describe "DEFAULTS" do
    it "freezes the defaults hash" do
      expect(described_class::DEFAULTS).to be_frozen
    end
  end
end

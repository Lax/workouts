RSpec.describe Workouts::Config do
  let(:config_path) { File.join(File.dirname(__FILE__), "fixtures", "test_config.yml") }

  before do
    dir = File.dirname(config_path)
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    File.write(config_path, <<~YAML)
      database:
        path: /tmp/test.db
      sync:
        strava:
          client_id: "123"
      privacy:
        start_end_range: 500
      export:
        json:
          path: /tmp/test.json
    YAML
  end

  after do
    File.delete(config_path) if File.exist?(config_path)
  end

  it "loads defaults" do
    config = Workouts::Config.new
    expect(config.db_path).to eq("data/db/workouts.db")
    expect(config.privacy_config["start_end_range"]).to eq(200)
  end

  it "loads YAML file" do
    config = Workouts::Config.new(config_path)
    expect(config.db_path).to eq("/tmp/test.db")
    expect(config.sync_config("strava")).to eq("client_id" => "123")
    expect(config.privacy_config["start_end_range"]).to eq(500)
    expect(config.export_config.dig("json", "path")).to eq("/tmp/test.json")
  end

  it "merges nested hashes" do
    config = Workouts::Config.new(config_path)
    expect(config["database"]).to eq("path" => "/tmp/test.db")
    expect(config["privacy"]["start_end_range"]).to eq(500)
  end

  it "returns empty hash for unknown sync source" do
    config = Workouts::Config.new
    expect(config.sync_config("nonexistent")).to eq({})
  end

  it "warns on unknown top-level key" do
    path = File.join(File.dirname(__FILE__), "fixtures", "bad_config.yml")
    File.write(path, <<~YAML)
      database:
        path: /tmp/test.db
      unknown_key:
        foo: bar
    YAML
    expect { Workouts::Config.new(path) }.to output(/unknown top-level key/).to_stderr
    File.delete(path) if File.exist?(path)
  end
end

RSpec.describe Workouts::Export::JSON do
  let(:db) do
    db_path = "/tmp/test_export.db"
    File.delete(db_path) if File.exist?(db_path)
    conn = Workouts::DB::Connection.new(db_path)
    conn.db
  end

  let(:output) { "/tmp/test_export.json" }

  before do
    now = Time.now.utc
    db[:activities].insert(
      run_id: "test_1", name: "Test Run", distance: 5000,
      moving_time: 1500, sport_category: "run",
      start_date: "2024-01-01T00:00:00Z", start_date_local: "2024-01-01T00:00:00Z",
      source: "test", created_at: now, updated_at: now
    )
  end

  after do
    File.delete(output) if File.exist?(output)
    File.delete("/tmp/test_export.db") if File.exist?("/tmp/test_export.db")
  end

  it "exports activities to JSON" do
    count = described_class.new(db: db, output: output).call
    expect(count).to eq(1)

    data = JSON.parse(File.read(output))
    expect(data).to be_an(Array)
    expect(data.length).to eq(1)
    expect(data[0]["run_id"]).to eq("test_1")
    expect(data[0]["type"]).to eq("run")
    expect(data[0]["distance"]).to eq(5000)
  end

  it "filters by sport category" do
    count = described_class.new(db: db, output: output, activity_filter: ["run"]).call
    expect(count).to eq(1)
  end

  it "returns 0 for non-matching filter" do
    count = described_class.new(db: db, output: output, activity_filter: ["ride"]).call
    expect(count).to eq(0)
  end

  it "formats moving time" do
    described_class.new(db: db, output: output).call
    data = JSON.parse(File.read(output))
    expect(data[0]["moving_time"]).to eq("0:25:00")
  end
end

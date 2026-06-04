RSpec.describe Workouts::Export::CSV do
  let(:db) do
    db_path = "/tmp/test_export_csv.db"
    File.delete(db_path) if File.exist?(db_path)
    conn = Workouts::DB::Connection.new(db_path)
    conn.db
  end

  let(:output) { "/tmp/test_export.csv" }

  before do
    now = Time.now.utc
    db[:activities].insert(
      run_id: "csv_1", name: "CSV Run", distance: 5000,
      moving_time: 1500, sport_category: "run",
      start_date: "2024-01-01T00:00:00Z", start_date_local: "2024-01-01T00:00:00Z",
      source: "test", created_at: now, updated_at: now
    )
  end

  after do
    File.delete(output) if File.exist?(output)
    File.delete("/tmp/test_export_csv.db") if File.exist?("/tmp/test_export_csv.db")
  end

  it "exports activities to CSV" do
    described_class.new(db: db, output: output).call
    lines = File.readlines(output)
    expect(lines.length).to eq(2)
    expect(lines[0]).to include("run_id")
    expect(lines[1]).to include("csv_1")
    expect(lines[1]).to include("5000")
  end

  it "writes headers correctly" do
    described_class.new(db: db, output: output).call
    headers = CSV.parse(File.read(output), headers: true).headers
    expect(headers).to include("run_id", "name", "distance", "sport_category")
  end

  it "filters by sport category" do
    described_class.new(db: db, output: output, activity_filter: ["run"]).call
    lines = File.readlines(output)
    expect(lines.length).to eq(2)
  end
end

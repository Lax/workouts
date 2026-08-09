RSpec.describe Workouts::CLI do
  it "registers auth command" do
    expect(described_class.commands).to include("auth")
  end

  it "registers db command" do
    expect(described_class.commands).to include("db")
  end

  it "registers geo command" do
    expect(described_class.commands).to include("geo")
  end

  it "registers init command" do
    expect(described_class.commands).to include("init")
  end

  it "registers parse command" do
    expect(described_class.commands).to include("parse")
  end

  it "registers version command" do
    expect(described_class.commands).to include("version")
  end

  it "delegates auth garmin to git fit auth garmin" do
    allow(GitFit::CLI).to receive(:start)
    GitFit::CLI.start(%w[auth garmin])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin"])
  end

  it "passes garmin strategy flags through to git fit" do
    allow(GitFit::CLI).to receive(:start)
    GitFit::CLI.start(%w[auth garmin -A])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin", "-A"])
  end

  it "passes --config through to git fit auth garmin" do
    allow(GitFit::CLI).to receive(:start)
    GitFit::CLI.start(%w[auth garmin -c custom.yml])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin", "-c", "custom.yml"])
  end
end

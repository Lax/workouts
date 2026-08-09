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
    Workouts::CLI.start(%w[auth garmin])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin"])
  end

  it "passes garmin strategy flags through to git fit" do
    allow(GitFit::CLI).to receive(:start)
    Workouts::CLI.start(%w[auth garmin -A])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin", "-A"])
  end

  it "passes --config through to git fit auth garmin" do
    allow(GitFit::CLI).to receive(:start)
    Workouts::CLI.start(%w[auth garmin -c custom.yml])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin", "-c", "custom.yml"])
  end

  it "passes --mfa-code through to git fit auth garmin" do
    allow(GitFit::CLI).to receive(:start)
    Workouts::CLI.start(%w[auth garmin --mfa-code 123456])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin", "--mfa-code", "123456"])
  end

  it "delegates auth garmin_cn to git fit auth garmin_cn" do
    allow(GitFit::CLI).to receive(:start)
    Workouts::CLI.start(%w[auth garmin_cn])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin_cn"])
  end

  it "delegates auth strava to git fit auth strava" do
    allow(GitFit::CLI).to receive(:start)
    Workouts::CLI.start(%w[auth strava])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "strava"])
  end

  it "passes --config through to git fit auth garmin_cn" do
    allow(GitFit::CLI).to receive(:start)
    Workouts::CLI.start(%w[auth garmin_cn -c custom.yml])
    expect(GitFit::CLI).to have_received(:start).with(["auth", "garmin_cn", "-c", "custom.yml"])
  end

  it "rejects auth xoss with a warn (self-authenticates during sync)" do
    expect { Workouts::CLI.start(%w[auth xoss]) }
      .to output(/self-authenticates during `git fit sync`/).to_stdout
  end

  it "rejects auth xingzhe with a warn (self-authenticates during sync)" do
    expect { Workouts::CLI.start(%w[auth xingzhe]) }
      .to output(/self-authenticates during `git fit sync`/).to_stdout
  end

  it "rejects unknown auth source" do
    expect { Workouts::CLI.start(%w[auth bogus]) }
      .to output(/Supported: garmin, garmin_cn, strava/).to_stdout
  end
end

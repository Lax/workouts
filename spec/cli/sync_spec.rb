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
end

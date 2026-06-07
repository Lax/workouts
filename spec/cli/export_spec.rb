RSpec.describe Workouts::ExportCLI do
  it "registers json command" do
    expect(described_class.commands).to include("json")
  end

  it "registers csv command" do
    expect(described_class.commands).to include("csv")
  end

  it "registers svg command" do
    expect(described_class.commands).to include("svg")
  end

  it "registers stats command" do
    expect(described_class.commands).to include("stats")
  end

  it "registers html command" do
    expect(described_class.commands).to include("html")
  end

  it "registers all command" do
    expect(described_class.commands).to include("all")
  end
end

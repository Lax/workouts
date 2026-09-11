# frozen_string_literal: true

RSpec.describe ".github/actions/danger-db-run" do
  let(:yaml) { YAML.safe_load_file(File.expand_path("../.github/actions/danger-db-run/action.yml", __dir__)) }
  let(:steps) { yaml.dig("runs", "steps") }

  it "pins setup-ruby to 3.4 with bundler cache" do
    setup = steps.find { |s| s["uses"] == "ruby/setup-ruby@v1" }
    expect(setup.dig("with", "ruby-version")).to eq("3.4")
    expect(setup.dig("with", "bundler-cache")).to be(true)
  end

  it "restores DB from GitFit/db branch in fallback mode" do
    restore = steps.find { |s| s["id"] == "db-restore" }
    expect(restore.dig("with", "git-restore-mode")).to eq("fallback")
    expect(restore.dig("with", "git-branch")).to eq("GitFit/db")
  end

  it "skips data-store restore when data-sources is empty" do
    data_restore = steps.find { |s| s["uses"] == "git-fit-actions/data-store/cache/restore@v2" }
    expect(data_restore["if"]).to eq("inputs.data-sources != ''")
  end

  it "gates DEM cache restore+save on the dem input and saves always()" do
    dem_restore = steps.find { |s| s["name"] == "[dem] Restore cache" }
    dem_save = steps.find { |s| s["name"] == "[dem] Save cache" }
    expect(dem_restore["if"]).to eq("inputs.dem == 'true'")
    expect(dem_save["if"]).to eq("always() && inputs.dem == 'true'")
  end

  it "runs the operation script with DB_PATH env between restore and saves" do
    op = steps.find { |s| s["id"] == "operation" }
    expect(op.dig("env", "DB_PATH")).to include("steps.db-paths.outputs.db-path")
    order = steps.map { |s| s["name"] || s["uses"] }
    expect(order.index("Operation")).to be > order.index("[db] Restore cache")
    expect(order.index("Operation")).to be < order.index("[db] Save cache")
  end

  it "gates DB save on always() && save input" do
    save = steps.find { |s| s["name"] == "[db] Save cache" }
    expect(save["if"]).to eq("always() && inputs.save == 'true'")
    expect(save.dig("with", "save-to-git-branch")).to eq(false)
  end
end

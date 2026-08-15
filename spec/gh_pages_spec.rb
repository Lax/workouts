# frozen_string_literal: true

RSpec.describe "gh-pages.yml" do
  let(:yaml) { load_workflow("gh-pages.yml") }
  let(:on_events) { workflow_on(yaml) }
  let(:job) { yaml.fetch("jobs").fetch("deploy-pages") }
  let(:steps) { job.fetch("steps") }

  describe "trigger" do
    it "runs after the CI workflow completes" do
      expect(on_events.dig("workflow_run", "workflows")).to eq(["CI"])
      expect(on_events.dig("workflow_run", "types")).to eq(["completed"])
    end

    it "gates deploy on manual dispatch or a successful CI run" do
      expect(job["if"]).to eq("${{ github.event_name == 'workflow_dispatch' || github.event.workflow_run.conclusion == 'success' }}")
    end
  end

  describe "checkout" do
    it "uses the PAT and the triggering workflow head sha" do
      checkout = steps.find { |s| s["uses"]&.start_with?("actions/checkout") }
      expect(checkout).not_to be_nil
      expect(checkout.dig("with", "token")).to eq("${{ secrets.WORKOUTS_SYNC_PAT }}")
      expect(checkout.dig("with", "ref")).to include("workflow_run.head_sha")
    end
  end

  describe "export and deploy" do
    it "exports JSON/Stats and deploys pages" do
      names = steps.map { |s| s["name"] }
      expect(names).to include("Export JSON")
      expect(names).to include("Export Stats")
      expect(steps.any? { |s| s["uses"]&.include?("actions/deploy-pages@v4") }).to be(true)
    end
  end

  describe "frontend build" do
    it "builds the UI from the vendored source after stats export" do
      build = steps.find { |s| s["name"] == "Build frontend UI" }
      expect(build).not_to be_nil
      expect(build.dig("uses")).to eq("./.github/git-fit-actions/frontend-build")
      expect(build.dig("with", "config")).to eq("config.json")
      expect(build.dig("with", "out-dir")).to eq("site")

      export_stats = steps.index { |s| s["name"] == "Export Stats" }
      expect(steps.index(build)).to be > export_stats
    end

    it "uses the local frontend-build composite action" do
      action = YAML.safe_load_file(File.expand_path("../.github/git-fit-actions/frontend-build/action.yml", __dir__))
      expect(action.dig("runs", "using")).to eq("composite")
      expect(action.fetch("inputs").keys).to include("config", "out-dir")
    end
  end
end

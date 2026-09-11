# frozen_string_literal: true

RSpec.describe "danger-correct-elevation.yml" do
  let(:yaml) { load_workflow("danger-correct-elevation.yml") }
  let(:job) { yaml.dig("jobs", "correct-elevation") }
  let(:steps) { job["steps"] }

  describe "triggers" do
    it "supports workflow_dispatch with source, force and dem inputs" do
      on = workflow_on(yaml)
      inputs = on.dig("workflow_dispatch", "inputs")
      expect(inputs).to have_key("source")
      expect(inputs["source"]["type"]).to eq("choice")
      expect(inputs["source"]["default"]).to eq("all")
      expect(inputs["source"]["options"]).to eq(%w[all igpsport keep xoss strava garmin garmin_cn xingzhe 2bulu apple_health codoon joyrun])

      expect(inputs).to have_key("force")
      expect(inputs["force"]["type"]).to eq("boolean")
      expect(inputs["force"]["default"]).to eq(false)

      expect(inputs).to have_key("dem")
      expect(inputs["dem"]["type"]).to eq("boolean")
      expect(inputs["dem"]["default"]).to eq(true)
    end

    it "has no schedule trigger (manual only)" do
      expect(workflow_on(yaml)["schedule"]).to be_nil
    end
  end

  describe "concurrency" do
    it "serializes against workouts-db without cancel-in-progress" do
      expect(job.dig("concurrency", "group")).to eq("workouts-db")
      expect(job.dig("concurrency", "cancel-in-progress")).to be(false)
    end
  end

  describe "operation" do
    let(:run) { steps.find { |s| s["uses"] == "./.github/actions/danger-db-run" } }

    it "uses the shared danger-db-run composite skeleton with DB save defaulting on" do
      expect(run).not_to be_nil
      expect(run.dig("with", "save")).to be_nil
    end

    it "passes DEM flag through and restores all eleven sources" do
      expect(run.dig("with", "dem")).to eq("${{ inputs.dem }}")
      sources = run.dig("with", "data-sources")
      expect(sources.split(",")).to match_array(%w[igpsport keep xoss strava garmin garmin_cn xingzhe 2bulu apple_health codoon joyrun])
    end

    it "runs git fit elevation correct, maps --no-dem and guards against exit-0 failure" do
      op = run.dig("with", "operation")
      expect(op).to include("git fit elevation correct")
      expect(op).to include("tee correct.out")
      expect(op).to include("grep -q 'Elevation correct:'")
      expect(op).to include("--no-dem")
      expect(op).to include('if [ "$DEM" != "true" ]')
      expect(op).to include("exit 1")
      expect(op).to include("no_model")
    end

    it "checkpoints only when updated > 0" do
      op = run.dig("with", "operation")
      expect(op).to include("wal_checkpoint.rb")
      expect(op).to include("UPDATED\" -gt 0")
    end
  end

  describe "summary" do
    it "reports source/force/dem/counters and warnings" do
      summary = steps.find { |s| s["name"] == "Summary" }
      run = summary["run"]
      expect(run).to include("### GitFit elevation correct")
      expect(run).to include("${{ inputs.dem }}")
      expect(run).to include("${{ steps.run.outputs.updated")
      expect(run).to include(".no_model")
      expect(run).to include("grep '^Elevation correct \\['")
    end
  end
end

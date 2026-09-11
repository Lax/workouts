# frozen_string_literal: true

RSpec.describe "danger-backfill-elevation.yml" do
  let(:yaml) { load_workflow("danger-backfill-elevation.yml") }
  let(:job) { yaml.dig("jobs", "backfill-elevation") }
  let(:steps) { job["steps"] }

  describe "triggers" do
    it "supports workflow_dispatch with source and force inputs" do
      on = workflow_on(yaml)
      inputs = on.dig("workflow_dispatch", "inputs")
      expect(inputs).to have_key("source")
      expect(inputs["source"]["type"]).to eq("choice")
      expect(inputs["source"]["default"]).to eq("all")
      expect(inputs["source"]["options"]).to eq(%w[all igpsport keep xoss strava garmin garmin_cn xingzhe])

      expect(inputs).to have_key("force")
      expect(inputs["force"]["type"]).to eq("boolean")
      expect(inputs["force"]["default"]).to eq(false)
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

    it "restores all nine elevation backfill sources" do
      sources = run.dig("with", "data-sources")
      expect(sources.split(",")).to match_array(%w[igpsport keep xoss strava garmin garmin_cn xingzhe codoon joyrun])
    end

    it "runs git fit elevation backfill, parses counters and guards against exit-0 failure" do
      op = run.dig("with", "operation")
      expect(op).to include("git fit elevation backfill")
      expect(op).to include("tee backfill.out")
      expect(op).to include("grep -q 'Elevation backfill:'")
      expect(op).to include("updated=$UPDATED")
      expect(op).to include("result=")
      expect(op).to include("exit 1")
    end

    it "checkpoints only when updated > 0" do
      op = run.dig("with", "operation")
      expect(op).to include("wal_checkpoint.rb")
      expect(op).to include("UPDATED\" -gt 0")
    end
  end

  describe "summary" do
    it "reports source/force/updated/skipped/failed" do
      summary = steps.find { |s| s["name"] == "Summary" }
      run = summary["run"]
      expect(run).to include("### GitFit elevation backfill")
      expect(run).to include("${{ inputs.source }}")
      expect(run).to include("${{ steps.run.outputs.updated")
      expect(run).to include(".skipped")
      expect(run).to include(".failed")
    end
  end
end

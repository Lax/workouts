# frozen_string_literal: true

RSpec.describe "danger-backfill.yml" do
  let(:yaml) { load_workflow("danger-backfill.yml") }
  let(:job) { yaml.dig("jobs", "backfill") }
  let(:steps) { job["steps"] }

  describe "triggers" do
    it "supports workflow_dispatch with source input" do
      on = workflow_on(yaml)
      inputs = on.dig("workflow_dispatch", "inputs")
      expect(inputs).to have_key("source")
      expect(inputs["source"]["type"]).to eq("string")
      expect(inputs["source"]["default"]).to eq("all")
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

    it "uses the shared danger-db-run composite skeleton" do
      expect(run).not_to be_nil
    end

    it "restores only the selected source's data cache" do
      expect(run.dig("with", "data-sources")).to include("inputs.source == 'all'")
      expect(run.dig("with", "data-sources")).to include("keep,strava,igpsport,garmin,garmin_cn")
    end

    it "runs all five backfill scripts behind source gates" do
      op = run.dig("with", "operation")
      expect(op).to include("backfill_keep_time.rb")
      expect(op).to include("backfill_garmin_sensors.rb")
      %w[keep strava igpsport garmin garmin_cn].each { |src| expect(op).to include("--source \"$src\"") }
    end

    it "sets GIT_FIT_SYSTEM_TIMEZONE for the keep branch" do
      op = run.dig("with", "operation")
      expect(op).to include("GIT_FIT_SYSTEM_TIMEZONE")
      expect(op).to include("Asia/Shanghai")
    end

    it "sums per-source updated counts from script stdout" do
      op = run.dig("with", "operation")
      expect(op).to include("total=$((total + ${n:-0}))")
      expect(op).to include("updated=$total")
    end

    it "checkpoints only when total > 0" do
      op = run.dig("with", "operation")
      expect(op).to include("wal_checkpoint.rb")
      expect(op).to include("total\" -gt 0")
    end
  end

  describe "summary" do
    it "reports source and total updated" do
      summary = steps.find { |s| s["name"] == "Summary" }
      expect(summary["run"]).to include("### GitFit datetime + temperature backfill")
      expect(summary["run"]).to include("steps.run.outputs.updated || 0")
    end
  end
end

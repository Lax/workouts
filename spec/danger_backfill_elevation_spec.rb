# frozen_string_literal: true

RSpec.describe "danger-backfill-elevation.yml" do
  let(:yaml) { load_workflow("danger-backfill-elevation.yml") }
  let(:content) { File.read(workflow_path("danger-backfill-elevation.yml")) }
  let(:steps) { yaml.dig("jobs", "backfill-elevation", "steps") }

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
      on = workflow_on(yaml)
      expect(on["schedule"]).to be_nil
    end
  end

  describe "concurrency" do
    it "serializes against workouts-db without cancel-in-progress" do
      concurrency = yaml.dig("jobs", "backfill-elevation", "concurrency")
      expect(concurrency["group"]).to eq("workouts-db")
      expect(concurrency["cancel-in-progress"]).to be(false)
    end
  end

  describe "DB cache restore" do
    it "restores from GitFit/db branch in fallback mode" do
      restore = steps.find { |s| s["name"]&.include?("[db] Restore cache") }
      expect(restore).not_to be_nil
      expect(restore.dig("with", "git-restore-mode")).to eq("fallback")
      expect(restore.dig("with", "git-branch")).to eq("GitFit/db")
    end
  end

  describe "data restore" do
    it "restores all seven elevation backfill sources" do
      data_restore = steps.find { |s| s["name"]&.include?("Restore data store") }
      expect(data_restore).not_to be_nil
      sources = data_restore.dig("with", "sources")
      expect(sources.split(",")).to match_array(%w[igpsport keep xoss strava garmin garmin_cn xingzhe])
    end
  end

  describe "backfill step" do
    it "runs git fit elevation backfill and parses output for updated/skipped/failed" do
      backfill = steps.find { |s| s["id"] == "backfill" }
      expect(backfill).not_to be_nil
      run = backfill["run"]
      expect(run).to include("git fit elevation backfill")
      expect(run).to include("tee backfill.out")
      expect(run).to include("grep -q 'Elevation backfill:'")
      expect(run).to include('echo "updated=$UPDATED"')
      expect(run).to include('echo "skipped=$SKIPPED"')
      expect(run).to include('echo "failed=$FAILED"')
    end

    it "guards against exit-0 failure trap with grep check" do
      backfill = steps.find { |s| s["id"] == "backfill" }
      expect(backfill["run"]).to include("exit 1")
    end
  end

  describe "conditional downstream" do
    it "DB save always runs (if: always())" do
      save = steps.find { |s| s["name"]&.include?("[db] Save cache") }
      expect(save).not_to be_nil
      expect(save["if"]).to eq("always()")
    end

    it "DB save is cache-only (no git push)" do
      save = steps.find { |s| s["name"]&.include?("[db] Save cache") }
      expect(save).not_to be_nil
      expect(save.dig("with", "save-to-git-branch")).to eq(false)
      expect(save.dig("with", "db-dir")).to include("steps.db-paths.outputs.dir")
      expect(save.dig("with", "db-name")).to include("steps.db-paths.outputs.name")
    end

    it "no gh-pages trigger step" do
      trigger = steps.find { |s| s["name"]&.include?("gh-pages") }
      expect(trigger).to be_nil
    end

    it "checkpoint runs only when updated > 0" do
      checkpoint = steps.find { |s| s["name"]&.include?("[db] Checkpoint") }
      expect(checkpoint).not_to be_nil
      expect(checkpoint["if"]).to include("steps.backfill.outputs.updated > 0")
    end
  end

  describe "action version pins" do
    it "pins actions to major tags" do
      uses = steps.map { |s| s["uses"] }.compact
      expect(uses).to include("actions/checkout@v7")
      expect(uses).to include("ruby/setup-ruby@v1")
      expect(uses).to include("git-fit-actions/db-store/paths@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/restore@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/save@v1")
      expect(uses).to include("git-fit-actions/data-store/cache/restore@v2")
    end
  end

  describe "summary" do
    it "writes step summary with source/force/updated/skipped/failed" do
      summary = steps.find { |s| s["name"]&.include?("Summary") }
      expect(summary).not_to be_nil
      run = summary["run"]
      expect(run).to include("### GitFit elevation backfill")
      expect(run).to include("${{ inputs.source }}")
      expect(run).to include("${{ inputs.force }}")
      expect(run).to include("${{ steps.backfill.outputs.updated")
    end
  end
end

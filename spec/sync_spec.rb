# frozen_string_literal: true

RSpec.describe "sync.yml" do
  let(:yaml) { load_workflow("sync.yml") }
  let(:content) { File.read(workflow_path("sync.yml")) }
  let(:steps) { yaml.dig("jobs", "sync", "steps") }

  describe "concurrency" do
    it "serializes against the scheduler via workouts-db group without cancel-in-progress" do
      expect(yaml.dig("jobs", "sync", "concurrency", "group")).to eq("workouts-db")
      expect(yaml.dig("jobs", "sync", "concurrency", "cancel-in-progress")).to be(false)
    end
  end

  describe "DB cache restore" do
    it "restores from the GitFit/db branch in fallback mode" do
      restore = steps.find { |s| s["name"] == "[db] Restore cache" }
      expect(restore.dig("with", "git-restore-mode")).to eq("fallback")
      expect(restore.dig("with", "git-branch")).to eq("GitFit/db")
    end
  end

  describe "git save passthrough chain" do
    it "gates git save on job success" do
      gate = steps.find { |s| s["name"] == "[db] Gate git save on job success" }
      expect(gate["if"]).to eq("success()")
      expect(gate["run"]).to include("steps.db-restore.outputs.save-to-git-branch")
    end

    it "passes the gate output into the DB cache save" do
      save = steps.find { |s| s["name"] == "[db] Save cache" }
      expect(save.dig("with", "save-to-git-branch")).to include("steps.git-save-gate.outputs.save-to-git-branch")
    end
  end

  describe "scheduler trigger" do
    it "conditionally triggers sync-scheduler on data/DB change" do
      trigger = steps.find { |s| s["name"] == "Trigger sync scheduler" }
      expect(trigger).not_to be_nil
      expect(trigger["if"]).to eq("steps.db-save.outputs.changed == 'true' || steps.data-save.outputs.changed == 'true'")
      expect(trigger["run"]).to include("gh workflow run")
      expect(trigger["run"]).to include("sync-scheduler.yml")
      expect(trigger["run"]).to include("-f commit=true")
    end
  end

  describe "PAT removal" do
    it "does not reference WORKOUTS_SYNC_PAT" do
      expect(content).not_to include("WORKOUTS_SYNC_PAT")
    end

    it "no longer runs an inline Manage sync cron step" do
      names = steps.map { |s| s["name"] }
      expect(names).not_to include("Manage sync cron")
    end
  end
end

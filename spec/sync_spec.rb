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

  describe "timeouts" do
    it "bounds the job runtime so a hung step cannot burn the default 6h billing budget" do
      expect(yaml.dig("jobs", "sync", "timeout-minutes")).to eq(30)
    end
  end

  describe "AI separation" do
    it "is data-only — no AI steps live here (ai-insights.yml owns the LLM path)" do
      names = steps.map { |s| s["name"] }
      expect(names.grep(/\[ai\]/)).to be_empty
      expect(content).not_to include("setup-opencode")
      expect(content).not_to include("GIT_FIT_AI")
      # 裸调用兜底：命名启发式拦不住不带 AI env 的 export ai run 步骤
      expect(content).not_to include("export ai")
    end

    it "dispatches ai-insights.yml with the sync run id on data/DB change" do
      trigger = steps.find { |s| s["name"] == "Trigger AI insights export" }
      expect(trigger).not_to be_nil
      expect(trigger["run"]).to include("gh workflow run ai-insights.yml")
      expect(trigger["run"]).to include("-f artifact-run-id=${{ github.run_id }}")
      expect(trigger["if"]).to eq("steps.db-save.outputs.changed == 'true' || steps.data-save.outputs.changed == 'true'")
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

  describe "summary convention" do
    it "removes the workflow-level summary block (actions write their own)" do
      names = steps.map { |s| s["name"] }
      expect(names).not_to include("Write DB summary")
      expect(names).not_to include("DB sync result")
    end
  end

  describe "action version pins" do
    it "pins data-store/db-store/import/geo-detect to major tags" do
      uses = steps.map { |s| s["uses"] }.compact
      expect(uses).to include("git-fit-actions/data-store/cache/restore@v2")
      expect(uses).to include("git-fit-actions/data-store/cache/save@v2")
      expect(uses).to include("git-fit-actions/db-store/paths@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/restore@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/save@v1")
      expect(uses).to include("git-fit-actions/import@v1")
      expect(uses).to include("git-fit-actions/geo-detect@v1")
    end
  end
end

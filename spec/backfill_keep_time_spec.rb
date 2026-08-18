# frozen_string_literal: true

RSpec.describe "backfill-keep-time.yml" do
  let(:yaml) { load_workflow("backfill-keep-time.yml") }
  let(:content) { File.read(workflow_path("backfill-keep-time.yml")) }
  let(:steps) { yaml.dig("jobs", "backfill", "steps") }

  describe "triggers" do
    it "supports workflow_dispatch" do
      on = workflow_on(yaml)
      expect(on).to have_key("workflow_dispatch")
    end

    it "runs weekly as a safety net" do
      on = workflow_on(yaml)
      schedule = on["schedule"]
      expect(schedule).to be_an(Array)
      expect(schedule.first["cron"]).to eq("0 4 * * 0")
    end
  end

  describe "concurrency" do
    it "serializes against workouts-db without cancel-in-progress" do
      concurrency = yaml.dig("jobs", "backfill", "concurrency")
      expect(concurrency["group"]).to eq("workouts-db")
      expect(concurrency["cancel-in-progress"]).to be(false)
    end
  end

  describe "DB cache restore" do
    it "restores from GitFit/db branch in fallback mode" do
      restore = steps.find { |s| s["name"]&.include?("Restore cache") }
      expect(restore).not_to be_nil
      expect(restore.dig("with", "git-restore-mode")).to eq("fallback")
      expect(restore.dig("with", "git-branch")).to eq("GitFit/db")
    end
  end

  describe "Keep data restore" do
    it "restores only keep source" do
      data_restore = steps.find { |s| s["uses"]&.include?("data-store/cache/restore") }
      expect(data_restore).not_to be_nil
      expect(data_restore.dig("with", "sources")).to eq("keep")
    end
  end

  describe "backfill script" do
    it "runs the backfill script" do
      backfill = steps.find { |s| s["id"] == "backfill" }
      expect(backfill).not_to be_nil
      expect(backfill["run"]).to include("backfill_keep_time.rb")
      expect(backfill["run"]).to include("--db-path")
    end

    it "sets GIT_FIT_SYSTEM_TIMEZONE" do
      backfill = steps.find { |s| s["id"] == "backfill" }
      expect(backfill.dig("env", "GIT_FIT_SYSTEM_TIMEZONE")).to include("Asia/Shanghai")
    end
  end

  describe "conditional downstream" do
    it "checkpoint runs only when updated > 0" do
      checkpoint = steps.find { |s| s["name"]&.downcase&.include?("checkpoint") }
      expect(checkpoint).not_to be_nil
      expect(checkpoint["if"]).to include("steps.backfill.outputs.updated > 0")
    end

    it "DB save always runs (SHA256 handles idempotency)" do
      save = steps.find { |s| s["name"]&.include?("Save cache") }
      expect(save).not_to be_nil
      expect(save["if"]).to eq("always()")
    end

    it "git save gate runs only when updated > 0" do
      gate = steps.find { |s| s["name"]&.include?("Gate git save") }
      expect(gate).not_to be_nil
      expect(gate["if"]).to include("steps.backfill.outputs.updated > 0")
    end

    it "gh-pages trigger runs only when updated > 0" do
      trigger = steps.find { |s| s["name"]&.include?("gh-pages") }
      expect(trigger).not_to be_nil
      expect(trigger["if"]).to include("steps.backfill.outputs.updated > 0")
    end
  end

  describe "action version pins" do
    it "pins db-store/data-store to major tags" do
      uses = steps.map { |s| s["uses"] }.compact
      expect(uses).to include("git-fit-actions/db-store/paths@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/restore@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/save@v1")
      expect(uses).to include("git-fit-actions/data-store/cache/restore@v2")
    end
  end
end

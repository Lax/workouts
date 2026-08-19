# frozen_string_literal: true

RSpec.describe "backfill.yml" do
  let(:yaml) { load_workflow("backfill.yml") }
  let(:content) { File.read(workflow_path("backfill.yml")) }
  let(:steps) { yaml.dig("jobs", "backfill", "steps") }

  describe "triggers" do
    it "supports workflow_dispatch with source input" do
      on = workflow_on(yaml)
      inputs = on.dig("workflow_dispatch", "inputs")
      expect(inputs).to have_key("source")
      expect(inputs["source"]["type"]).to eq("string")
      expect(inputs["source"]["default"]).to eq("all")
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

  describe "data restore" do
    it "restores only keep source when source=keep" do
      data_restore = steps.find { |s| s["name"]&.include?("Restore keep") }
      expect(data_restore).not_to be_nil
      expect(data_restore["if"]).to include("inputs.source")
    end

    it "restores strava data when source=strava" do
      strava_restore = steps.find { |s| s["name"]&.include?("Restore strava") }
      expect(strava_restore).not_to be_nil
      expect(strava_restore.dig("with", "sources")).to eq("strava")
      expect(strava_restore["if"]).to include("inputs.source")
    end

    it "restores igpsport data when source=igpsport" do
      igpsport_restore = steps.find { |s| s["name"]&.include?("Restore igpsport") }
      expect(igpsport_restore).not_to be_nil
      expect(igpsport_restore.dig("with", "sources")).to eq("igpsport")
      expect(igpsport_restore["if"]).to include("inputs.source")
    end

    it "restores garmin data when source=garmin" do
      garmin_restore = steps.find { |s| s["name"]&.include?("Restore garmin data") }
      expect(garmin_restore).not_to be_nil
      expect(garmin_restore.dig("with", "sources")).to eq("garmin")
      expect(garmin_restore["if"]).to include("inputs.source")
    end

    it "restores garmin_cn data when source=garmin_cn" do
      garmin_cn_restore = steps.find { |s| s["name"]&.include?("Restore garmin_cn data") }
      expect(garmin_cn_restore).not_to be_nil
      expect(garmin_cn_restore.dig("with", "sources")).to eq("garmin_cn")
      expect(garmin_cn_restore["if"]).to include("inputs.source")
    end
  end

  describe "backfill steps" do
    it "runs Keep backfill with --source keep" do
      keep = steps.find { |s| s["id"] == "backfill-keep" }
      expect(keep).not_to be_nil
      expect(keep["run"]).to include("backfill_keep_time.rb")
      expect(keep["run"]).to include("--source keep")
    end

    it "runs Strava backfill with --source strava" do
      strava = steps.find { |s| s["id"] == "backfill-strava" }
      expect(strava).not_to be_nil
      expect(strava["run"]).to include("--source strava")
    end

    it "runs iGPSPORT backfill with --source igpsport" do
      igpsport = steps.find { |s| s["id"] == "backfill-igpsport" }
      expect(igpsport).not_to be_nil
      expect(igpsport["run"]).to include("--source igpsport")
    end

    it "Keep backfill sets GIT_FIT_SYSTEM_TIMEZONE" do
      keep = steps.find { |s| s["id"] == "backfill-keep" }
      expect(keep.dig("env", "GIT_FIT_SYSTEM_TIMEZONE")).to include("Asia/Shanghai")
    end

    it "runs Garmin backfill with --source garmin" do
      garmin = steps.find { |s| s["id"] == "backfill-garmin" }
      expect(garmin).not_to be_nil
      expect(garmin["run"]).to include("backfill_garmin_temperature.rb")
      expect(garmin["run"]).to include("--source garmin")
    end

    it "runs Garmin CN backfill with --source garmin_cn" do
      garmin_cn = steps.find { |s| s["id"] == "backfill-garmin-cn" }
      expect(garmin_cn).not_to be_nil
      expect(garmin_cn["run"]).to include("backfill_garmin_temperature.rb")
      expect(garmin_cn["run"]).to include("--source garmin_cn")
    end
  end

  describe "total updates computation" do
    it "sums updates from all backfill steps" do
      total = steps.find { |s| s["id"] == "total" }
      expect(total).not_to be_nil
      expect(total["run"]).to include("backfill-keep")
      expect(total["run"]).to include("backfill-strava")
      expect(total["run"]).to include("backfill-igpsport")
      expect(total["run"]).to include("backfill-garmin")
      expect(total["run"]).to include("backfill-garmin-cn")
    end
  end

  describe "conditional downstream" do
    it "checkpoint runs only when total updated > 0" do
      checkpoint = steps.find { |s| s["name"]&.downcase&.include?("checkpoint") }
      expect(checkpoint).not_to be_nil
      expect(checkpoint["if"]).to include("steps.total.outputs.updated > 0")
    end

    it "DB save always runs (SHA256 handles idempotency)" do
      save = steps.find { |s| s["name"]&.include?("Save cache") }
      expect(save).not_to be_nil
      expect(save["if"]).to eq("always()")
    end

    it "git save gate runs only when total updated > 0" do
      gate = steps.find { |s| s["name"]&.include?("Gate git save") }
      expect(gate).not_to be_nil
      expect(gate["if"]).to include("steps.total.outputs.updated > 0")
    end

    it "gh-pages trigger runs only when total updated > 0" do
      trigger = steps.find { |s| s["name"]&.include?("gh-pages") }
      expect(trigger).not_to be_nil
      expect(trigger["if"]).to include("steps.total.outputs.updated > 0")
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

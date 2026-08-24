# frozen_string_literal: true

RSpec.describe "danger-correct-elevation.yml" do
  let(:yaml) { load_workflow("danger-correct-elevation.yml") }
  let(:content) { File.read(workflow_path("danger-correct-elevation.yml")) }
  let(:steps) { yaml.dig("jobs", "correct-elevation", "steps") }

  describe "triggers" do
    it "supports workflow_dispatch with source, force and dem inputs" do
      on = workflow_on(yaml)
      inputs = on.dig("workflow_dispatch", "inputs")
      expect(inputs).to have_key("source")
      expect(inputs["source"]["type"]).to eq("choice")
      expect(inputs["source"]["default"]).to eq("all")
      expect(inputs["source"]["options"]).to eq(%w[all igpsport xoss strava garmin garmin_cn xingzhe])

      expect(inputs).to have_key("force")
      expect(inputs["force"]["type"]).to eq("boolean")
      expect(inputs["force"]["default"]).to eq(false)

      expect(inputs).to have_key("dem")
      expect(inputs["dem"]["type"]).to eq("boolean")
      expect(inputs["dem"]["default"]).to eq(true)
    end

    it "has no schedule trigger (manual only)" do
      on = workflow_on(yaml)
      expect(on["schedule"]).to be_nil
    end
  end

  describe "concurrency" do
    it "serializes against workouts-db without cancel-in-progress" do
      concurrency = yaml.dig("jobs", "correct-elevation", "concurrency")
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
    it "restores all six elevation sources" do
      data_restore = steps.find { |s| s["name"]&.include?("Restore data store") }
      expect(data_restore).not_to be_nil
      sources = data_restore.dig("with", "sources")
      expect(sources.split(",")).to match_array(%w[igpsport xoss strava garmin garmin_cn xingzhe])
    end
  end

  describe "DEM cache" do
    it "restores data/cache/dem* with independent prefix key" do
      restore = steps.find { |s| s["name"] == "Restore DEM cache" }
      expect(restore).not_to be_nil
      expect(restore["uses"]).to eq("actions/cache/restore@v4")
      paths = restore.dig("with", "path").split("\n").map(&:strip)
      expect(paths).to contain_exactly("data/cache/dem", "data/cache/dem_fit")
      expect(restore.dig("with", "key")).to start_with("GitFit-dem-v0-")
      expect(restore.dig("with", "restore-keys")).to eq("GitFit-dem-v0-")
    end

    it "saves DEM cache always() with the same key namespace" do
      save = steps.find { |s| s["name"] == "Save DEM cache" }
      expect(save).not_to be_nil
      expect(save["uses"]).to eq("actions/cache/save@v4")
      expect(save["if"]).to eq("always()")
      expect(save.dig("with", "key")).to include("github.run_id")
    end

    it "never pushes DEM cache to GitFit/* git branches" do
      content_str = content
      expect(content_str).not_to match(/GitFit\/data/)
      git_branch_pushes = steps.select { |s| s["uses"].to_s.include?("cache/save") && s.dig("with", "key").to_s.start_with?("GitFit-dem") }
      expect(git_branch_pushes).to all(satisfy { |s| !s.dig("with").key?("git-branch") })
    end
  end

  describe "correct step" do
    it "runs git fit elevation correct and parses updated/skipped/failed/no_model" do
      correct = steps.find { |s| s["id"] == "correct" }
      expect(correct).not_to be_nil
      run = correct["run"]
      expect(run).to include("git fit elevation correct")
      expect(run).to include("tee correct.out")
      expect(run).to include("grep -q 'Elevation correct:'")
      expect(run).to include('echo "updated=$UPDATED"')
      expect(run).to include('echo "skipped=$SKIPPED"')
      expect(run).to include('echo "failed=$FAILED"')
      expect(run).to include('echo "no_model=$NO_MODEL"')
    end

    it "maps dem input to --no-dem flag when disabled" do
      correct = steps.find { |s| s["id"] == "correct" }
      expect(correct["run"]).to include("--no-dem")
      expect(correct["run"]).to include('if [ "$DEM" != "true" ]')
    end

    it "guards against exit-0 failure trap with grep check" do
      correct = steps.find { |s| s["id"] == "correct" }
      expect(correct["run"]).to include("exit 1")
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
      expect(checkpoint["if"]).to include("steps.correct.outputs.updated > 0")
    end
  end

  describe "action version pins" do
    it "pins actions to major tags" do
      uses = steps.map { |s| s["uses"] }.compact
      expect(uses).to include("actions/checkout@v6")
      expect(uses).to include("ruby/setup-ruby@v1")
      expect(uses).to include("git-fit-actions/db-store/paths@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/restore@v1")
      expect(uses).to include("git-fit-actions/db-store/cache/save@v1")
      expect(uses).to include("git-fit-actions/data-store/cache/restore@v2")
      expect(uses).to include("actions/cache/restore@v4")
      expect(uses).to include("actions/cache/save@v4")
    end
  end

  describe "summary" do
    it "writes step summary with source/force/dem/counters" do
      summary = steps.find { |s| s["name"]&.include?("Summary") }
      expect(summary).not_to be_nil
      run = summary["run"]
      expect(run).to include("### GitFit elevation correct")
      expect(run).to include("${{ inputs.source }}")
      expect(run).to include("${{ inputs.force }}")
      expect(run).to include("${{ inputs.dem }}")
      expect(run).to include("${{ steps.correct.outputs.updated")
      expect(run).to include("${{ steps.correct.outputs.no_model")
    end

    it "includes correct warnings in summary" do
      summary = steps.find { |s| s["name"]&.include?("Summary") }
      expect(summary["run"]).to include("grep '^Elevation correct \\['")
    end
  end
end

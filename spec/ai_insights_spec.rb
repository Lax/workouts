# frozen_string_literal: true

RSpec.describe "ai-insights.yml" do
  let(:yaml) { load_workflow("ai-insights.yml") }
  let(:on_events) { workflow_on(yaml) }
  let(:job) { yaml.fetch("jobs").fetch("ai-insights") }
  let(:content) { File.read(workflow_path("ai-insights.yml")) }
  let(:steps) { job.fetch("steps") }

  describe "trigger" do
    it_behaves_like "a dispatch-only workflow"

    it "accepts an optional sync run id for the fresh DB artifact" do
      inputs = on_events.fetch("workflow_dispatch").fetch("inputs")
      expect(inputs).to have_key("artifact-run-id")
      expect(inputs.fetch("artifact-run-id").fetch("required")).to eq(false)
    end
  end

  describe "isolation" do
    it "cancels superseded exports — queued serial runs would amplify quota burn" do
      expect(job.dig("concurrency", "group")).to eq("ai-insights")
      expect(job.dig("concurrency", "cancel-in-progress")).to be(true)
    end

    it "bounds the opencode install (remote network call) with a step-level timeout" do
      setup = steps.find { |s| s["name"] == "[ai] Setup opencode CLI" }
      expect(setup["timeout-minutes"]).to eq(5)
    end

    it "never gates the publish chain — dispatch fires only on changed insights" do
      dispatch = steps.find { |s| s["name"] == "Trigger pages deploy (fresh insights)" }
      expect(dispatch).not_to be_nil
      expect(dispatch["if"]).to eq("steps.ai-export.outputs.changed == 'true'")
    end
  end

  describe "timeouts" do
    it "bounds the job runtime so a hung export cannot burn the default 6h billing budget" do
      expect(job["timeout-minutes"]).to eq(30)
    end

    it "bounds the AI export step above the gem-fixed legal envelope (3x2x180s = 18min)" do
      ai = steps.find { |s| s["id"] == "ai-export" }
      expect(ai["timeout-minutes"]).to eq(20)
      # 无 continue-on-error：失败/超时直接红本 workflow，旧 insights 原样保留
      expect(ai).not_to have_key("continue-on-error")
    end
  end

  describe "content integrity" do
    it "validates the exported JSON before cache save and dispatch" do
      ai = steps.find { |s| s["id"] == "ai-export" }
      # 顺序锁定：jq 校验闸必须先于 changed 计算（校验失败时 changed 不落盘）
      expect(ai["run"]).to match(/jq -e \. site\/insights\.json[\s\S]*changed=true/)
      expect(ai["run"]).to include("exit 1")
    end

    it "gates cache save and pages dispatch on a valid changed export" do
      save = steps.find { |s| s["name"] == "[ai] Save cache" }
      dispatch = steps.find { |s| s["name"] == "Trigger pages deploy (fresh insights)" }
      expect(save.dig("with", "key")).to include("GitFit-ai-insights-v0-${{ github.run_id }}")
      expect(dispatch["run"]).to include("gh workflow run gh-pages.yml")
      expect(dispatch["run"]).to include("-f artifact-run-id=${{ inputs.artifact-run-id }}")
    end
  end

  describe "fresh db" do
    it "restores the DB cache and optionally downloads the sync artifact" do
      restore = steps.find { |s| s["uses"]&.start_with?("git-fit-actions/db-store/cache/restore") }
      expect(restore).not_to be_nil

      download = steps.find { |s| s["name"] == "Download fresh DB artifact" }
      expect(download["if"]).to eq("inputs.artifact-run-id != ''")
      expect(download["continue-on-error"]).to be(true)
      expect(download.dig("with", "name")).to eq("workouts-db")
    end
  end

  describe "transport gating" do
    it "installs opencode only for the opencode transport" do
      setup = steps.find { |s| s["name"] == "[ai] Setup opencode CLI" }
      expect(setup["if"]).to eq("env.AI_TRANSPORT == 'opencode'")
    end

    it "skips export when openai transport lacks an API key (secrets via job env)" do
      export = steps.find { |s| s["id"] == "ai-export" }
      expect(export["if"]).to eq("env.AI_TRANSPORT != 'openai' || env.AI_API_KEY_PRESENT == 'true'")
      expect(job.fetch("env")).to include("AI_TRANSPORT" => "${{ vars.AI_TRANSPORT || 'opencode' }}")
      expect(job.fetch("env")).to have_key("AI_API_KEY_PRESENT")
    end
  end
end

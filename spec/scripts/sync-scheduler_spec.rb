# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("../..", __dir__)
CRON_N_REGEX = %r{/\K\d+(?= \* \*)}

RSpec.describe "cron management split" do
  let(:sync_workflow) { File.expand_path("../../.github/workflows/sync.yml", __dir__) }
  let(:scheduler_workflow) { File.expand_path("../../.github/workflows/sync-scheduler.yml", __dir__) }
  let(:sync_yaml) { YAML.safe_load_file(sync_workflow) }
  let(:scheduler_yaml) { YAML.safe_load_file(scheduler_workflow) }
  let(:scheduler_steps) { scheduler_yaml.dig("jobs", "manage", "steps") }

  # The "Read current cron interval" step is now inlined into sync-scheduler.yml.

  def read_step_run
    step = scheduler_steps.find { |s| s["id"] == "read" }
    step.fetch("run")
  end

  describe "Read current cron interval step" do
    it "uses a grep regex matching the cron interval in sync.yml" do
      run = read_step_run
      expect(run).to include(".github/workflows/sync.yml")
      expect(run).to include("grep -oP")
      expect(run).to include("/\\K\\d+(?= \\* \\*)")
    end

    it "extracts N from a cron line matching the regex" do
      line = "- cron: '0 2 */2 * *'"
      m = line.match(CRON_N_REGEX)
      expect(m&.to_s).to eq("2")
    end

    it "does not match a daily cron (no */N)" do
      line = "- cron: '0 2 * * *'"
      expect(line.match(CRON_N_REGEX)).to be_nil
    end
  end

  describe "sync-scheduler.yml structure" do
    it "triggers on workflow_dispatch with a commit choice input" do
      on_key = scheduler_yaml.key?(true) ? scheduler_yaml[true] : scheduler_yaml["on"]
      inputs = on_key.dig("workflow_dispatch", "inputs")
      expect(inputs).to have_key("commit")
      expect(inputs.dig("commit", "type")).to eq("choice")
      expect(inputs.dig("commit", "default")).to eq("false")
    end

    it "serializes against the sync job via workouts-db concurrency group" do
      expect(scheduler_yaml.dig("jobs", "manage", "concurrency", "group")).to eq("workouts-db")
    end

    it "configures git with PAT extraheader (the only PAT writer)" do
      git_step = scheduler_steps.find { |s| s["name"] == "Configure git" }
      expect(git_step).not_to be_nil
      expect(git_step["env"]).to have_key("WORKOUTS_SYNC_PAT")
    end

    it "restores DB cache before reading/computing the interval" do
      names = scheduler_steps.map { |s| s["name"] }
      restore_idx = names.index("[db] Restore cache")
      read_idx = names.index { |n| n&.start_with?("Read current") }
      expect(restore_idx).not_to be_nil
      expect(read_idx).not_to be_nil
      expect(restore_idx).to be < read_idx
    end

    it "commits only when commit input is true and git is configured" do
      manage_step = scheduler_steps.find { |s| s["id"] == "manage" }
      expect(manage_step).not_to be_nil
      run = manage_step.fetch("run")
      expect(run).to include('[ "$COMMIT" = "true" ]')
      expect(run).to include('[ "$GIT_CONFIGURED" = "true" ]')
      expect(run).not_to include("GITHUB_EVENT_NAME")
    end
  end

  describe "sync.yml split" do
    let(:sync_steps) { sync_yaml.dig("jobs", "sync", "steps") }

    it "no longer runs an inline Manage sync cron step" do
      names = sync_steps.map { |s| s["name"] }
      expect(names).not_to include("Manage sync cron")
    end

    it "conditionally triggers sync-scheduler on schedule events" do
      trigger = sync_steps.find { |s| s["name"] == "Trigger sync scheduler" }
      expect(trigger).not_to be_nil
      expect(trigger["if"]).to eq("github.event_name == 'schedule'")
      expect(trigger["run"]).to include("sync-scheduler.yml")
      expect(trigger["run"]).to include("-f commit=true")
    end

    it "places the trigger after DB cache save" do
      names = sync_steps.map { |s| s["name"] }
      save_idx = names.index("[db] Save cache")
      trigger_idx = names.index("Trigger sync scheduler")
      expect(save_idx).not_to be_nil
      expect(trigger_idx).not_to be_nil
      expect(save_idx).to be < trigger_idx
    end

    it "no longer references WORKOUTS_SYNC_PAT (PAT moved to sync-scheduler)" do
      content = File.read(sync_workflow)
      expect(content).not_to include("WORKOUTS_SYNC_PAT")
    end

    it "uses default checkout credentials (no persist-credentials: false)" do
      checkout = sync_steps.find { |s| s["uses"]&.start_with?("actions/checkout") }
      expect(checkout).not_to be_nil
      expect(checkout["with"]).to be_nil
    end

    it "passes git-configured: 'true' to import-apple-health" do
      apple = sync_steps.find { |s| s["uses"]&.end_with?("import-apple-health") }
      expect(apple.dig("with", "git-configured")).to eq("true")
    end
  end
end

# frozen_string_literal: true

CRON_N_REGEX = %r{/\K\d+(?= \* \*)}

RSpec.describe "sync-scheduler.yml" do
  let(:yaml) { load_workflow("sync-scheduler.yml") }
  let(:on_events) { workflow_on(yaml) }
  let(:steps) { yaml.dig("jobs", "manage", "steps") }
  let(:read_run) { steps.find { |s| s["id"] == "read" }.fetch("run") }

  describe "Read current cron interval step" do
    it "uses a grep regex matching the cron interval in sync.yml" do
      expect(read_run).to include(".github/workflows/sync.yml")
      expect(read_run).to include("grep -oP")
      expect(read_run).to include("/\\K\\d+(?= \\* \\*)")
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

  describe "adaptive cron interval" do
    it "runs the read → compute → update steps in order" do
      names = steps.map { |s| s["name"] }
      read_idx = names.index { |n| n == "Read current cron interval" }
      compute_idx = names.index { |n| n == "Compute new interval" }
      update_idx = names.index { |n| n == "Update sync.yml cron" }
      expect(read_idx).not_to be_nil
      expect(compute_idx).not_to be_nil
      expect(update_idx).not_to be_nil
      expect(read_idx).to be < compute_idx
      expect(compute_idx).to be < update_idx
    end

    it "computes the new interval from DB freshness" do
      run = steps.find { |s| s["name"] == "Compute new interval" }.fetch("run")
      expect(run).to include("f < n")
      expect(run).to include("f > 2 * n + 1")
      expect(run).to include("new_n=")
    end

    it "updates sync.yml cron via sed" do
      run = steps.find { |s| s["name"] == "Update sync.yml cron" }.fetch("run")
      expect(run).to include("sed -i")
      expect(run).to include(".github/workflows/sync.yml")
    end
  end

  describe "structure" do
    it "triggers on workflow_dispatch with a commit choice input and a 7-day schedule fallback" do
      inputs = on_events.dig("workflow_dispatch", "inputs")
      expect(inputs).to have_key("commit")
      expect(inputs.dig("commit", "type")).to eq("choice")
      expect(inputs.dig("commit", "default")).to eq("false")

      schedule = on_events.dig("schedule")
      expect(schedule).not_to be_nil
      expect(schedule.map { |s| s["cron"] }).to include("0 3 * * 0")
    end

    it "serializes against the sync job via workouts-db concurrency group" do
      expect(yaml.dig("jobs", "manage", "concurrency", "group")).to eq("workouts-db")
    end

    it "uses persist-credentials: false (no token input passed to checkout)" do
      checkout = steps.find { |s| s["uses"]&.start_with?("actions/checkout") }
      expect(checkout).not_to be_nil
      expect(checkout.dig("with", "persist-credentials")).to be(false)
      expect(checkout.dig("with", "token")).to be_nil
    end

    it "configures git with bare PAT extraheader" do
      git_step = steps.find { |s| s["name"] == "Configure git" }
      expect(git_step).not_to be_nil
      expect(git_step["if"]).to eq("${{ github.event_name == 'schedule' || inputs.commit == 'true' }}")
      expect(git_step["env"]).to have_key("WORKOUTS_SYNC_PAT")
      expect(git_step["run"]).to include("printf '%s:'")
      expect(git_step["run"]).to include("base64 -w0")
      expect(git_step["run"]).to include("configured=false")
      expect(git_step["run"]).to include("configured=true")
    end

    it "uses git-auto-commit-action for commit step" do
      commit_step = steps.find { |s| s["uses"]&.include?("git-auto-commit-action") }
      expect(commit_step).not_to be_nil
      expect(commit_step.dig("with", "file_pattern")).to eq(".github/workflows/sync.yml")
      expect(commit_step.dig("with", "commit_user_name")).to eq("workouts-bot")
      expect(commit_step.dig("with", "commit_message")).to include("[skip ci]")
    end

    it "has only contents:write in permissions (workflows not valid in permissions block)" do
      perms = yaml.dig("jobs", "manage", "permissions")
      expect(perms).to eq("contents" => "write")
    end

    it "gates commit steps on schedule/commit input and git configuration" do
      update_step = steps.find { |s| s["name"] == "Update sync.yml cron" }
      expect(update_step["if"]).to eq("${{ github.event_name == 'schedule' || inputs.commit == 'true' }}")

      commit_step = steps.find { |s| s["uses"]&.include?("git-auto-commit-action") }
      expect(commit_step["if"]).to eq("${{ (github.event_name == 'schedule' || inputs.commit == 'true') && steps.git-setup.outputs.configured == 'true' }}")
    end

    it "restores DB cache before reading/computing the interval" do
      names = steps.map { |s| s["name"] }
      restore_idx = names.index("[db] Restore cache")
      read_idx = names.index { |n| n&.start_with?("Read current") }
      expect(restore_idx).not_to be_nil
      expect(read_idx).not_to be_nil
      expect(restore_idx).to be < read_idx
    end
  end
end

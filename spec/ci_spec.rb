# frozen_string_literal: true

RSpec.describe "ci.yml" do
  let(:yaml) { load_workflow("ci.yml") }
  let(:jobs) { yaml.fetch("jobs") }

  shared_examples "a structurally complete job" do |job_name|
    let(:job) { jobs.fetch(job_name) }

    it "#{job_name} declares minimal permissions" do
      expect(job["permissions"]).to be_a(Hash)
      expect(job["permissions"]).not_to be_empty
    end

    it "#{job_name} declares a non-conflicting concurrency group" do
      concurrency = job["concurrency"]
      expect(concurrency).not_to be_nil
      expect(concurrency.fetch("group")).not_to be_nil
      expect(concurrency.fetch("group")).not_to eq("workouts-db")
      expect([true, false]).to include(concurrency.fetch("cancel-in-progress"))
    end

    it "#{job_name} declares a positive timeout-minutes" do
      timeout = job["timeout-minutes"]
      expect(timeout).to be_a(Integer)
      expect(timeout).to be > 0
    end

    it "#{job_name} ends with exactly one always() summary step" do
      summaries = job.fetch("steps").select { |s| s["run"].to_s.include?("$GITHUB_STEP_SUMMARY") }
      expect(summaries.size).to eq(1)
      expect(summaries.first.fetch("if")).to eq("always()")
    end
  end

  it "runs exactly three jobs" do
    expect(jobs.keys).to contain_exactly("workflow-lint", "ruby-test", "deploy-gate")
  end

  describe "workflow-lint" do
    it_behaves_like "a structurally complete job", "workflow-lint"

    it "lints workflows with actionlint and shellcheck off" do
      lint = jobs.fetch("workflow-lint")
      step = lint.dig("steps").find { |s| s["uses"]&.start_with?("raven-actions/actionlint") }
      expect(step).not_to be_nil
      expect(step.dig("with", "shellcheck")).to be(false)
    end

    it "runs on a pinned hosted image (actionlint needs npm, missing on self-hosted; pinned ahead of the 2026-10 ubuntu-26 label migration)" do
      expect(jobs.fetch("workflow-lint")["runs-on"]).to eq("ubuntu-24.04")
    end
  end

  describe "ruby-test" do
    it_behaves_like "a structurally complete job", "ruby-test"

    it "runs rspec on Ruby 3.4 only" do
      job = jobs.fetch("ruby-test")
      expect(job.dig("strategy", "matrix", "ruby-version")).to eq(["3.4"])
      runs = job.dig("steps").map { |s| s["run"] }
      expect(runs).to include("bundle exec rspec")
    end
  end

  describe "deploy-gate" do
    it_behaves_like "a structurally complete job", "deploy-gate"

    it "waits for both jobs and only gates direct pushes to master" do
      job = jobs.fetch("deploy-gate")
      expect(job["needs"]).to contain_exactly("workflow-lint", "ruby-test")
      expect(job["if"]).to include("github.event_name == 'push'")
      expect(job["if"]).to include("refs/heads/master")
    end

    it "queues instead of cancelling so a qualifying push cannot lose its dispatch" do
      concurrency = jobs.fetch("deploy-gate").fetch("concurrency")
      expect(concurrency.fetch("cancel-in-progress")).to be(false)
    end

    it "holds only contents:read and actions:write" do
      expect(jobs.fetch("deploy-gate")["permissions"]).to eq("contents" => "read", "actions" => "write")
    end

    it "gates on site-affecting paths" do
      gate = jobs.fetch("deploy-gate")["steps"].find { |s| s["name"] == "Detect site-affecting changes" }
      expect(gate).not_to be_nil
      # 站点产物输入：站点/运行配置、前端 npm 锁、gem 锁（导出行为）、赛事数据、部署工作流自身
      ['config\.json', 'config\.yml', 'package(-lock)?\.json', 'Gemfile\.lock', '\.env', "data/events/", '\.github/workflows/gh-pages\.yml'].each do |path|
        expect(gate["run"]).to include(path)
      end
    end

    it "dispatches gh-pages with the default token when the gate passes" do
      trigger = jobs.fetch("deploy-gate")["steps"].find { |s| s["name"] == "Trigger pages deploy" }
      expect(trigger.dig("if")).to eq("steps.gate.outputs.deploy == 'true'")
      expect(trigger["run"]).to include("gh workflow run gh-pages.yml --ref master")
      expect(trigger.dig("env", "GH_TOKEN")).to eq("${{ github.token }}")
    end
  end
end

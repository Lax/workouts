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

  it "runs exactly two jobs" do
    expect(jobs.keys).to contain_exactly("workflow-lint", "ruby-test")
  end

  describe "workflow-lint" do
    it_behaves_like "a structurally complete job", "workflow-lint"

    it "lints workflows with actionlint and shellcheck off" do
      lint = jobs.fetch("workflow-lint")
      step = lint.dig("steps").find { |s| s["uses"]&.start_with?("raven-actions/actionlint") }
      expect(step).not_to be_nil
      expect(step.dig("with", "shellcheck")).to be(false)
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
end

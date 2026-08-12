# frozen_string_literal: true

RSpec.describe "ci.yml" do
  let(:yaml) { load_workflow("ci.yml") }
  let(:jobs) { yaml.fetch("jobs") }

  it "runs exactly three jobs" do
    expect(jobs.keys).to contain_exactly("workflow-lint", "test-import-action", "ruby-test")
  end

  describe "workflow-lint" do
    it "lints workflows with actionlint and shellcheck off" do
      lint = jobs.fetch("workflow-lint")
      step = lint.dig("steps").find { |s| s["uses"]&.start_with?("raven-actions/actionlint") }
      expect(step).not_to be_nil
      expect(step.dig("with", "shellcheck")).to be(false)
    end
  end

  describe "test-import-action" do
    it "runs the import action node test suite" do
      job = jobs.fetch("test-import-action")
      expect(job.dig("defaults", "run", "working-directory")).to eq(".github/git-fit-actions/import")
      runs = job.dig("steps").map { |s| s["run"] }
      expect(runs).to include("npm ci")
      expect(runs).to include("npm run typecheck")
      expect(runs).to include("npm test")
      expect(runs).to include("npm run build:check")
    end
  end

  describe "ruby-test" do
    it "runs rspec on Ruby 3.4 only" do
      job = jobs.fetch("ruby-test")
      expect(job.dig("strategy", "matrix", "ruby-version")).to eq(["3.4"])
      expect(job.dig("steps").last.fetch("run")).to eq("bundle exec rspec")
    end
  end
end

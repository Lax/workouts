# frozen_string_literal: true

RSpec.describe "probe-pat-permissions.yml" do
  let(:yaml) { load_workflow("probe-pat-permissions.yml") }
  let(:job) { yaml.fetch("jobs").fetch("probe") }

  it "has a single probe job on the configured runner" do
    expect(yaml.fetch("jobs").keys).to eq(["probe"])
    expect(job["runs-on"]).to eq("${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}")
  end

  it "probes PAT via the dedicated action" do
    probe = job.fetch("steps").find { |s| s["uses"]&.include?("probe-pat-permissions") }
    expect(probe).not_to be_nil
    expect(probe.dig("with", "pat_token")).to eq("${{ secrets.WORKOUTS_SYNC_PAT }}")
  end

  it "always displays probe results to the step summary" do
    display = job.fetch("steps").find { |s| s["name"] == "Display probe results" }
    expect(display["if"]).to eq("always()")
    expect(display["run"]).to include("$GITHUB_STEP_SUMMARY")
  end
end

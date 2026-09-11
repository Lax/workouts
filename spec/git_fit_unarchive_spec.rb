# frozen_string_literal: true

RSpec.describe "git-fit-unarchive.yml" do
  include_examples "a dispatch-only workflow"

  let(:yaml) { load_workflow("git-fit-unarchive.yml") }
  let(:jobs) { yaml.fetch("jobs") }

  describe "unarchive-data job" do
    let(:job) { jobs.fetch("unarchive-data") }

    it "is gated to run only for non-db sources" do
      expect(job["if"]).to eq("${{ inputs.source != 'db' }}")
    end

    it "writes a run-suffixed snapshot cache key distinct from the sentinel" do
      key = job.dig("steps").find { |s| s["uses"]&.include?("actions/cache/save") }.dig("with", "key")
      expect(key).to include("GitFit-data-${{ matrix.source }}-v0-snapshot-${{ github.run_number }}-${{ github.run_id }}")
      expect(key).not_to include("-v0-sentinel")
    end
  end

  describe "unarchive-db job" do
    let(:job) { jobs.fetch("unarchive-db") }

    it "is gated to run for db or empty source" do
      expect(job["if"]).to eq("${{ inputs.source == 'db' || inputs.source == '' }}")
    end

    it "writes a run-suffixed snapshot cache key" do
      key = job.dig("steps").find { |s| s["uses"]&.include?("actions/cache/save") }.dig("with", "key")
      expect(key).to include("GitFit-db-v0-snapshot-${{ github.run_number }}-${{ github.run_id }}")
    end
  end
end

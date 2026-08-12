# frozen_string_literal: true

RSpec.describe "git-fit-archive.yml" do
  let(:yaml) { load_workflow("git-fit-archive.yml") }
  let(:jobs) { yaml.fetch("jobs") }

  describe "archive job" do
    let(:job) { jobs.fetch("archive") }
    let(:steps) { job.fetch("steps") }

    it "archives all 7 sources by default with fail-fast off" do
      expect(job.dig("strategy", "fail-fast")).to be(false)
      matrix = job.dig("strategy", "matrix", "source")
      expect(matrix).to include('["keep","igpsport","xoss","xingzhe","garmin","garmin_cn","strava"]')
    end

    it "serializes per-source via archive-<source> concurrency" do
      expect(job.dig("concurrency", "group")).to eq("archive-${{ matrix.source }}")
      expect(job.dig("concurrency", "cancel-in-progress")).to be(false)
    end

    it "restores cache via sentinel exact key under the -v0- prefix" do
      restore = steps.find { |s| s["uses"]&.include?("actions/cache/restore") }
      expect(restore).not_to be_nil
      expect(restore.dig("with", "key")).to include("-v0-sentinel")
      expect(restore.dig("with", "restore-keys")).to eq("GitFit-data-${{ matrix.source }}-v0-")
    end

    it "excludes pure deletions from the archive commit" do
      run = steps.find { |s| s["name"] == "Commit & push" }.fetch("run")
      expect(run).to include("--diff-filter=D")
      expect(run).to include("git reset HEAD")
    end
  end

  describe "archive-db job" do
    it "serializes against workouts-db concurrency" do
      expect(jobs.dig("archive-db", "concurrency", "group")).to eq("workouts-db")
    end
  end
end

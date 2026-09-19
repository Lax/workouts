# frozen_string_literal: true

require "json"

RSpec.describe "gh-pages.yml" do
  let(:yaml) { load_workflow("gh-pages.yml") }
  let(:on_events) { workflow_on(yaml) }
  let(:job) { yaml.fetch("jobs").fetch("deploy-pages") }
  let(:steps) { job.fetch("steps") }

  describe "trigger" do
    it_behaves_like "a dispatch-only workflow"

    it "no longer auto-runs on CI completion — deploy gating lives in ci.yml deploy-gate" do
      expect(on_events).not_to have_key("workflow_run")
      expect(job["if"]).to be_nil
    end
  end

  describe "checkout" do
    it "uses the default token and master head — PAT holder stays sync-scheduler only" do
      checkout = steps.find { |s| s["uses"]&.start_with?("actions/checkout") }
      expect(checkout).not_to be_nil
      expect(checkout["with"]).to be_nil
      expect(File.read(workflow_path("gh-pages.yml"))).not_to include("WORKOUTS_SYNC_PAT")
    end

    it "grants contents: read — default-token checkout 404s without it (PAT masked this before)" do
      expect(job.fetch("permissions")).to include("contents" => "read")
    end
  end

  describe "export and deploy" do
    it "exports JSON/Stats and deploys pages" do
      names = steps.map { |s| s["name"] }
      expect(names).to include("Export JSON")
      expect(names).to include("Export Stats")
      expect(steps.any? { |s| s["uses"]&.include?("actions/deploy-pages@v5") }).to be(true)
    end

    it "exports ability snapshots after stats, ungated (no LLM needed)" do
      ability = steps.find { |s| s["name"] == "Export ability snapshots" }
      expect(ability).not_to be_nil
      expect(ability["run"]).to include("git fit ability compute --output site/ability.json")
      expect(ability["if"]).to be_nil

      export_stats = steps.index { |s| s["name"] == "Export Stats" }
      expect(steps.index(ability)).to be > export_stats
    end
  end

  describe "frontend build" do
    it "builds the UI from published @lax packages after stats export" do
      build = steps.find { |s| s["name"] == "Build frontend UI" }
      expect(build).not_to be_nil
      expect(build.dig("uses")).to eq("git-fit-actions/frontend-build@v1")
      expect(build.dig("with", "config")).to eq("config.build.json")
      expect(build.dig("with", "out-dir")).to eq("site")
      expect(build.dig("with", "npm-auth-token")).to eq("${{ secrets.GIT_FIT_NPM_TOKEN }}")

      export_stats = steps.index { |s| s["name"] == "Export Stats" }
      expect(steps.index(build)).to be > export_stats
    end

    it "selects the maptiler vendor with a secret-injected token through a temporary build config" do
      create = steps.find { |s| s["name"] == "Create frontend build config" }
      expect(create).not_to be_nil
      expect(create["run"]).to include("config.build.json")
      expect(create["run"]).to include("mapTileVendor = \"maptiler\"")
      expect(create["run"]).to include("mapTileToken = $token")
      expect(create["run"]).to include("del(.mapTileStyle)")
      expect(create["run"]).not_to include("del(.mapTileToken)")
      expect(create.dig("env", "MAPTILER_TOKEN")).to eq("${{ secrets.MAPTILER_TOKEN }}")

      build = steps.find { |s| s["name"] == "Build frontend UI" }
      expect(steps.index(create)).to be < steps.index(build)

      cleanup = steps.find { |s| s["name"] == "Remove generated frontend build config" }
      expect(cleanup["run"]).to include("rm -f config.build.json")
    end

    it "smoke-checks the MapTiler token with browser-accurate referer and degrade-and-report semantics" do
      smoke = steps.find { |s| s["name"] == "Verify map tile token" }
      expect(smoke).not_to be_nil
      expect(smoke["run"]).to include("api.maptiler.com")
      expect(smoke["run"]).to include("darkmatter")
      expect(smoke["run"]).to include("bright-v2")
      # MapTiler keys are domain-locked: keyless curls 403, and browsers send
      # origin-only Referer for cross-origin tile <img> requests — so the smoke
      # check must replicate that exact header shape.
      expect(smoke["run"]).to include("Referer: https://liulantao.com/")
      expect(smoke.dig("env", "MAPTILER_TOKEN")).to eq("${{ secrets.MAPTILER_TOKEN }}")

      # Degrade, don't block: the deploy must proceed when the token is
      # missing/invalid so the rest of the site (activities/stats) stays fresh.
      expect(smoke["run"]).to include("GITHUB_STEP_SUMMARY")
      expect(smoke["run"]).to include("::warning::")
      expect(smoke["run"]).not_to include("exit 1")

      races = steps.index { |s| s["name"] == "Stage races.json" }
      create = steps.index { |s| s["name"] == "Create frontend build config" }
      expect(steps.index(smoke)).to be > races
      expect(steps.index(smoke)).to be < create
    end

    it "grants packages: read for installing private @lax packages" do
      expect(job.fetch("permissions")).to include("packages" => "read")
    end
  end

  describe "config.json (site frontend config)" do
    let(:config) { JSON.parse(File.read(File.expand_path("../config.json", __dir__))) }

    it "declares the stats entry backed by theme-stats" do
      expect(config.dig("entries", "stats")).to eq("stats")
      expect(config.dig("entries", "index")).to eq("timeline")
      expect(config.dig("entries", "about")).to eq("hello-world")
    end

    it "declares the console entry backed by theme-console between stats and ai" do
      keys = config.fetch("entries").keys
      expect(config.dig("entries", "console")).to eq("console")
      expect(keys.index("console")).to be > keys.index("stats")
      expect(keys.index("console")).to be < keys.index("ai")
    end

    it "configures a per-theme title for console" do
      expect(config.dig("themes", "console", "site", "title")).to eq("控制台")
      expect(config.dig("themes", "console", "site", "nav")).to eq(false)
      expect(config.dig("themes", "console", "site", "palette")).to eq("mono")
    end

    it "adds a console nav label" do
      expect(config.dig("site", "nav", "labels", "console")).to eq("控制台")
    end

    it "declares stats/races data sources" do
      expect(config.dig("data", "stats")).to eq("source" => "stats.json", "optional" => false)
      expect(config.dig("data", "races")).to eq("source" => "races.json", "optional" => true)
    end

    it "configures a per-theme title for stats" do
      expect(config.dig("themes", "stats", "site", "title")).to eq("Stats")
    end

    it "does not commit a map tile token" do
      expect(config.dig("themes", "running-page", "site")).not_to have_key("mapTileToken")
    end

    it "uses the generic current-user logo token without a user-specific committed avatar" do
      expect(config.dig("site", "logo")).to eq("github:current-user")
      expect(config.dig("themes", "running-page", "site")).not_to have_key("logo")
    end
  end
end

# frozen_string_literal: true

# 数据源列表跨 workflow 一致性锁定。2026-11-27 教训：#94 新增 codoon/joyrun 时
# sync/data-store 升级了源列表，但 git-fit-archive/unarchive 的默认 matrix 漏更——
# 两个源从此没有 git 归档兜底（cache LRU 逐出即失兜底）。各 workflow 的源列表
# 独立维护必然漂移，这里用 sync 的 data-store 源列表为单一真值锁死全部分叉。
RSpec.describe "data source list consistency" do
  let(:sync_yaml) { load_workflow("sync.yml") }
  let(:sync_steps) { sync_yaml.dig("jobs", "sync", "steps") }
  let(:sync_restore_sources) do
    restore = sync_steps.find { |s| s["uses"]&.start_with?("git-fit-actions/data-store/cache/restore") }
    restore.dig("with", "sources").split(",").sort
  end

  # matrix 默认值嵌在 fromJson 表达式的 `|| '["a","b"]'` 兜底分支里
  def matrix_defaults(workflow, job)
    expr = load_workflow(workflow).dig("jobs", job, "strategy", "matrix", "source")
    expr[/\|\| '\[(.*)\]'\)\s*\}\}\s*$/, 1].split('","').map { |s| s.delete('"') }.sort
  end

  def dispatch_source_options(workflow)
    workflow_on(load_workflow(workflow))
      .fetch("workflow_dispatch").fetch("inputs").fetch("source")
      .fetch("options") - ["", "db"]
  end

  it "sync restores and saves identical data-store source lists" do
    save = sync_steps.find { |s| s["uses"]&.start_with?("git-fit-actions/data-store/cache/save") }
    expect(save.dig("with", "sources").split(",").sort).to eq(sync_restore_sources)
  end

  it "archive default matrix covers exactly the sync data-store sources" do
    expect(matrix_defaults("git-fit-archive.yml", "archive")).to eq(sync_restore_sources)
  end

  it "unarchive default matrix covers exactly the sync data-store sources" do
    expect(matrix_defaults("git-fit-unarchive.yml", "unarchive-data")).to eq(sync_restore_sources)
  end

  it "archive/unarchive dispatch options match their default matrices" do
    expect(dispatch_source_options("git-fit-archive.yml").sort).to eq(matrix_defaults("git-fit-archive.yml", "archive"))
    expect(dispatch_source_options("git-fit-unarchive.yml").sort).to eq(matrix_defaults("git-fit-unarchive.yml", "unarchive-data"))
  end

  # danger-* 系的数据源列表（#94 漏更的第二批发现：purge 白名单 / device options）
  def danger_data_sources(workflow)
    step = load_workflow(workflow).dig("jobs").values.flat_map { |j| j["steps"] || [] }
      .find { |s| s.dig("with", "data-sources") }
    step.dig("with", "data-sources").split(",").sort
  end

  def danger_options(workflow)
    workflow_on(load_workflow(workflow))
      .fetch("workflow_dispatch").fetch("inputs").fetch("source")
      .fetch("options").sort - ["all"]
  end

  it "purge delete-flags whitelist covers every sync data-store source" do
    content = File.read(workflow_path("danger-purge-activity.yml"))
    whitelist = content[/case "\$src" in\s*\n\s*(\S+)\)\s*;;/, 1]
    expect(whitelist.split("|").map(&:strip).sort).to eq(sync_restore_sources)
  end

  it "backfill-device data-sources matches sync and its options cover them" do
    expect(danger_data_sources("danger-backfill-device.yml")).to eq(sync_restore_sources)
    expect(danger_options("danger-backfill-device.yml")).to include(*sync_restore_sources)
  end

  it "backfill-elevation options match its data-sources (minus all)" do
    sources = danger_data_sources("danger-backfill-elevation.yml")
    expect(sources).to eq(sync_restore_sources)
    expect(danger_options("danger-backfill-elevation.yml")).to eq(sources)
  end

  it "correct-elevation options match its data-sources (minus all)" do
    expect(danger_options("danger-correct-elevation.yml")).to eq(danger_data_sources("danger-correct-elevation.yml"))
  end
end

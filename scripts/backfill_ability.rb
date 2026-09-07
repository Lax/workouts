#!/usr/bin/env ruby
# frozen_string_literal: true

# 一次性回填：运动能力画像全历史快照 → site/ability.json（#53，设计见 wiki/Ability）
#
# 前置：本地 SQLite（默认 data/db/workouts.db，可用 GIT_FIT_DATABASE_PATH 覆盖）
#       + 已实现 `git fit ability` CLI 的 git-fit（git-fit#95；未发版时本脚本不可用）。
# 幂等：compute 全量输出只依赖 DB 内容（generated_at 除外），重复执行安全。
# 产物：site/ 为 gitignored 构建制品，不入 git；线上由 sync/gh-pages 每次重算
#       （与 insights.json 同模式，#51 接线），本脚本仅用于本地全量生成/校验。
#
# 用法:
#   bundle exec ruby scripts/backfill_ability.rb [--output site/ability.json] [--db data/db/workouts.db]
#
# 依赖链: git-fit#95 → 本脚本 → #51（CI 数据流）

require "json"
require "fileutils"
require "optparse"

options = {
  output: "site/ability.json",
  db: ENV["GIT_FIT_DATABASE_PATH"] || "data/db/workouts.db"
}

OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby scripts/backfill_ability.rb [options]"
  opts.on("--output PATH", "输出路径（默认 site/ability.json）") { |v| options[:output] = v }
  opts.on("--db PATH", "SQLite DB 路径（默认 data/db/workouts.db，覆盖 GIT_FIT_DATABASE_PATH）") { |v| options[:db] = v }
end.parse!

unless File.exist?(options[:db])
  abort "backfill_ability: DB 不存在 — #{options[:db]}\n" \
        "  Fix: GIT_FIT_DATABASE_PATH=<路径> bundle exec ruby scripts/backfill_ability.rb"
end

# DB 有内容才值得回填；空库走 gem 侧空骨架语义（warn + exit 0）
rows = `sqlite3 #{options[:db].shellescape} "SELECT COUNT(*) FROM activities" 2>/dev/null`.to_i
if rows.zero?
  abort "backfill_ability: DB 无 activities 表或为空 — #{options[:db]}\n" \
        "  Fix: 先跑 sync 或确认 GIT_FIT_DATABASE_PATH（当前 #{options[:db]}）"
end

cmd = %w[bundle exec git fit ability compute --output] + [options[:output]]
unless system(*cmd)
  warn "backfill_ability: git fit ability compute 失败（exit #{$?.exitstatus}）\n" \
       "  Fix: bundle update git-fit  # ability CLI 需 git-fit#95 发版（>= 0.25）后可用"
  exit 1
end

doc = JSON.parse(File.read(options[:output]))
fitness = doc.dig("fitness", "snapshots") || []
sports = (doc["sports"] || {}).transform_values { |s| (s["snapshots"] || []).size }
conf = fitness.group_by { |s| s["confidence"] }.transform_values(&:size)

puts "backfill_ability: #{rows} activities -> #{options[:output]}"
puts "  fitness: #{fitness.size} 期快照（confidence: #{conf.map { |k, v| "#{k}=#{v}" }.join(" / ")}）"
puts "  sports: #{sports.empty? ? "无" : sports.map { |k, v| "#{k}=#{v}" }.join(" / ")}"

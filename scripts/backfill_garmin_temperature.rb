#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotent backfill: restore average_temperature for garmin / garmin_cn
# activities from the cached raw detail.json (direct Connect API response).
#
# History: build_attrs read summaryDTO['avgTemperature'], but the API returns
# 'averageTemperature'. Every garmin/garmin_cn row got NULL (FIT fallback only
# fires for activities that carry per-point temperature). This script reads the
# canonical summary value from the raw file and reconciles the DB.
#
# Only writes when the raw summary provides a value. Activities without a
# temperature in raw keep their existing DB value (or nil). Idempotent.
#
# Usage:
#   bundle exec ruby scripts/backfill_garmin_temperature.rb [options]
#
# Options:
#   --db-path PATH       SQLite database path (default: data/db/workouts.db)
#   --source SOURCE      Source to backfill (garmin, garmin_cn, all; default: all)
#   --raw-dir DIR        Raw data directory (default: data/raw/<source>)
#   --dry-run            Report only, do not write to database
#
# Outputs (GitHub Actions):
#   updated=N            Number of rows actually modified

require "json"
require "sequel"
require "optparse"

DEFAULT_DB = "data/db/workouts.db"

options = {
  db_path: DEFAULT_DB,
  source: "all",
  raw_dir: nil,
  dry_run: false
}

OptionParser.new do |opts|
  opts.on("--db-path PATH") { |v| options[:db_path] = v }
  opts.on("--source SOURCE") { |v| options[:source] = v }
  opts.on("--raw-dir DIR") { |v| options[:raw_dir] = v }
  opts.on("--dry-run") { options[:dry_run] = true }
end.parse!

VALID_SOURCES = %w[garmin garmin_cn all].freeze
TARGET_SOURCES = (options[:source] == "all") ? %w[garmin garmin_cn] : [options[:source]]

unless VALID_SOURCES.include?(options[:source])
  warn "backfill: unsupported source '#{options[:source]}'. Supported: #{VALID_SOURCES.join(", ")}"
  exit 1
end

db_path = options[:db_path]
dry_run = options[:dry_run]

unless File.exist?(db_path)
  warn "backfill: database not found: #{db_path}"
  exit 1
end

db = Sequel.sqlite(db_path)
db.run("PRAGMA journal_mode=WAL")

def raw_summary_temperature(raw_dir, source, run_id)
  platform_id = run_id.to_s.sub(/\A#{Regexp.escape(source)}_/, "")
  raw_path = File.join(raw_dir, platform_id, "detail.json")
  return nil unless File.exist?(raw_path)

  detail = JSON.parse(File.read(raw_path))
  temp = detail.dig("summaryDTO", "averageTemperature")
  return nil if temp.nil?

  Float(temp)
rescue JSON::ParserError, ArgumentError
  nil
end

updated = 0
skipped = 0
missing = 0

TARGET_SOURCES.each do |source|
  raw_dir = options[:raw_dir] || File.join("data", "raw", source)
  rows = db[:activities].where(source: source).all
  puts "backfill [#{source}]: #{rows.size} activities in DB"

  rows.each do |row|
    run_id = row[:run_id]
    current = row[:average_temperature]
    target = raw_summary_temperature(raw_dir, source, run_id)

    if target.nil?
      missing += 1
      next
    end

    if current == target
      skipped += 1
      next
    end

    unless dry_run
      db[:activities].where(run_id: run_id).update(
        average_temperature: target,
        updated_at: Time.now.utc
      )
    end

    updated += 1
    before = current.nil? ? "null" : current
    puts "  #{run_id}: average_temperature #{before} -> #{target}"
  end
end

db.disconnect

puts ""
puts "backfill: done"
puts "  updated: #{updated}"
puts "  skipped: #{skipped}"
puts "  missing: #{missing} (no averageTemperature in raw detail.json)"
puts "  dry-run: #{dry_run}" if dry_run

# GitHub Actions output
if ENV["GITHUB_OUTPUT"]
  File.open(ENV["GITHUB_OUTPUT"], "a") do |f|
    f.puts "updated=#{updated}"
  end
end

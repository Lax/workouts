#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotent backfill: restore Garmin sensor fields (temperature, cadence,
# power) for garmin / garmin_cn activities from the cached raw detail.json
# (direct Connect API response).
#
# History: build_attrs read non-existent short summaryDTO keys
# (avgTemperature / avgPower / avgCadence / avgRunning* / avgBiking*). The API
# returns spelled-out keys: averageTemperature, averagePower, and sport-scoped
# cadence (averageBikeCadence / maxBikeCadence for rides, averageRunCadence /
# maxRunCadence otherwise). Rows were written with NULL for those fields.
# This script reads the canonical summary values from raw and reconciles the DB.
#
# Only writes when the raw summary provides a value. Activities without a
# sensor field in raw keep their existing DB value (or nil). Idempotent.
#
# Usage:
#   bundle exec ruby scripts/backfill_garmin_sensors.rb [options]
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

DIRECT_KEYS = {
  average_temperature: "averageTemperature",
  average_power: "averagePower",
  max_power: "maxPower"
}.freeze

def sport_key(column, sport)
  return DIRECT_KEYS[column] if DIRECT_KEYS.key?(column)

  bike = (sport == "ride")
  prefix = (column == :average_cadence) ? "average" : "max"
  bike ? "#{prefix}BikeCadence" : "#{prefix}RunCadence"
end

# Returns {column => [current, target]} for every sensor field that has a
# canonical value in the raw summaryDTO. Empty hash when the raw file is
# missing or carries no sensor data.
def target_changes(raw_dir, source, row)
  platform_id = row[:run_id].to_s.sub(/\A#{Regexp.escape(source)}_/, "")
  raw_path = File.join(raw_dir, platform_id, "detail.json")
  return {} unless File.exist?(raw_path)

  summary = JSON.parse(File.read(raw_path)).dig("summaryDTO") || {}
  sport = row[:sport_category].to_s

  %i[average_temperature average_cadence max_cadence average_power max_power]
    .filter_map do |col|
    target = Float(summary[sport_key(col, sport)])
    # Cadence/power of 0 mean "no sensor"; temperature 0 is a valid reading.
    next if col != :average_temperature && target <= 0

    current = row[col]
    next if current == target

    [col, [current, target]]
  rescue ArgumentError, TypeError
    nil
  end.to_h
rescue JSON::ParserError
  {}
end

updated = 0
missing = 0

TARGET_SOURCES.each do |source|
  raw_dir = options[:raw_dir] || File.join("data", "raw", source)
  rows = db[:activities].where(source: source).all
  puts "backfill [#{source}]: #{rows.size} activities in DB"

  rows.each do |row|
    run_id = row[:run_id]
    changes = target_changes(raw_dir, source, row)

    if changes.empty?
      missing += 1
      next
    end

    unless dry_run
      updates = changes.transform_values(&:last).merge(updated_at: Time.now.utc)
      db[:activities].where(run_id: run_id).update(updates)
    end

    updated += 1
    changes.each do |col, (before, after)|
      b = before.nil? ? "null" : before
      puts "  #{run_id}: #{col} #{b} -> #{after}"
    end
  end
end

db.disconnect

puts ""
puts "backfill: done"
puts "  updated: #{updated}"
puts "  missing: #{missing} (no sensor values in raw detail.json)"
puts "  dry-run: #{dry_run}" if dry_run

# GitHub Actions output
if ENV["GITHUB_OUTPUT"]
  File.open(ENV["GITHUB_OUTPUT"], "a") do |f|
    f.puts "updated=#{updated}"
  end
end

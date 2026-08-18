#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotent backfill: fix naive datetime strings in DB for Keep activities.
#
# Problem: Keep activities synced by old gem versions stored start_date and
# start_date_local as naive "YYYY-MM-DD HH:MM:SS" (no timezone marker).
# The current gem (v0.13.1) produces ISO 8601 with "T" and offset, but old
# records are never updated because upsert_from_raw bails out for no-GPS
# activities (return false unless wgs&.any?) and the DB rebuild/restore cycle
# preserves the old values.
#
# This script re-reads raw files, recomputes correct values, and only writes
# when the DB value differs. Repeated runs with no changes produce zero
# updates (verified: db-store/cache/save SHA256 checksums stay identical).
#
# Usage:
#   bundle exec ruby scripts/backfill_keep_time.rb [options]
#
# Options:
#   --db-path PATH       SQLite database path (default: data/db/workouts.db)
#   --raw-dir DIR        Keep raw data directory (default: data/raw/keep)
#   --std-dir DIR        Keep std data directory (default: data/std/keep)
#   --dry-run            Report only, do not write to database
#
# Outputs (GitHub Actions):
#   updated=N            Number of rows actually modified

require "json"
require "sequel"
require "optparse"
require "time"

DEFAULT_DB = "data/db/workouts.db"
DEFAULT_RAW = "data/raw/keep"
DEFAULT_STD = "data/std/keep"

options = {
  db_path: DEFAULT_DB,
  raw_dir: DEFAULT_RAW,
  std_dir: DEFAULT_STD,
  dry_run: false
}

OptionParser.new do |opts|
  opts.on("--db-path PATH") { |v| options[:db_path] = v }
  opts.on("--raw-dir DIR") { |v| options[:raw_dir] = v }
  opts.on("--std-dir DIR") { |v| options[:std_dir] = v }
  opts.on("--dry-run") { options[:dry_run] = true }
end.parse!

# --- Helpers ---

def load_std_first_point(std_dir, keep_id)
  std_path = File.join(std_dir, "#{keep_id}.json")
  return nil unless File.exist?(std_path)

  std = JSON.parse(File.read(std_path))
  return nil unless std.is_a?(Array) && std.any?

  lat = std[0]["latitude"]
  lng = std[0]["longitude"]
  return nil unless lat && lng && lat != 0.0 && lng != 0.0

  [lat, lng]
rescue JSON::ParserError
  nil
end

def region_coords(raw_data)
  region = raw_data.dig("meta", "region")
  return nil unless region.is_a?(Hash)

  lat = region["latitude"]
  lng = region["longitude"]
  return nil unless lat && lng && lat != 0.0 && lng != 0.0

  [lat, lng]
end

def load_finder
  require "timezone_finder"
  TimezoneFinder.create
end

def resolve_tz(finder, lat, lng, default_tz)
  tz = finder.timezone_at(lat: lat.to_f, lng: lng.to_f)
  tz = default_tz if tz.nil? || (tz.is_a?(String) && tz.empty?)
  tz
end

def compute_target_values(raw_data, keep_id, std_dir, finder, default_tz)
  meta = raw_data["meta"]
  start_ms = meta["startTime"]
  return nil unless start_ms

  start_utc = Time.at(start_ms / 1000.0).utc
  target_start_date = start_utc.iso8601

  # Prefer GPS points from std; fall back to region lat/lng
  gps_point = load_std_first_point(std_dir, keep_id)
  region_point = region_coords(raw_data)

  lat, lng = gps_point || region_point
  if lat && lng
    tz_str = resolve_tz(finder, lat, lng, default_tz)
    require "tzinfo"
    tz = TZInfo::Timezone.get(tz_str)
    target_start_date_local = tz.utc_to_local(start_utc).iso8601
  else
    # No coordinates at all — store UTC ISO 8601 (with Z)
    target_start_date_local = start_utc.iso8601
  end

  {start_date: target_start_date, start_date_local: target_start_date_local}
end

# --- Main ---

db_path = options[:db_path]
raw_dir = options[:raw_dir]
dry_run = options[:dry_run]

unless File.exist?(db_path)
  warn "backfill: database not found: #{db_path}"
  exit 1
end

unless File.directory?(raw_dir)
  warn "backfill: raw directory not found: #{raw_dir}"
  exit 1
end

default_tz = ENV["GIT_FIT_SYSTEM_TIMEZONE"] || "Asia/Shanghai"

db = Sequel.sqlite(db_path)
db.run("PRAGMA journal_mode=WAL")

rows = db[:activities].where(source: "keep").all
puts "backfill: #{rows.size} Keep activities in DB"

finder = load_finder

updated = 0
skipped = 0
errors = 0
raw_missing = 0

rows.each do |row|
  run_id = row[:run_id]
  keep_id = run_id.to_s.sub(/\Akeep_/, "")

  raw_path = File.join(raw_dir, "#{keep_id}.json")
  unless File.exist?(raw_path)
    raw_missing += 1
    next
  end

  raw_data = JSON.parse(File.read(raw_path))
  targets = compute_target_values(raw_data, keep_id, options[:std_dir], finder, default_tz)

  unless targets
    warn "backfill: #{run_id}: cannot compute targets (missing startTime)"
    errors += 1
    next
  end

  current_sd = row[:start_date]
  current_sdl = row[:start_date_local]

  if current_sd == targets[:start_date] && current_sdl == targets[:start_date_local]
    skipped += 1
    next
  end

  # Value differs — update
  unless dry_run
    updates = {updated_at: Time.now.utc}
    updates[:start_date] = targets[:start_date] if current_sd != targets[:start_date]
    updates[:start_date_local] = targets[:start_date_local] if current_sdl != targets[:start_date_local]
    db[:activities].where(run_id: run_id).update(updates)
  end

  updated += 1
  if updated <= 5 || updated % 100 == 0
    puts "  #{run_id}: #{current_sdl} -> #{targets[:start_date_local]}"
  end
end

db.disconnect

# Summary
puts ""
puts "backfill: done"
puts "  total:   #{rows.size}"
puts "  updated: #{updated}"
puts "  skipped: #{skipped}"
puts "  missing: #{raw_missing}"
puts "  errors:  #{errors}"
puts "  dry-run: #{dry_run}" if dry_run

# GitHub Actions output
if ENV["GITHUB_OUTPUT"]
  File.open(ENV["GITHUB_OUTPUT"], "a") do |f|
    f.puts "updated=#{updated}"
  end
end

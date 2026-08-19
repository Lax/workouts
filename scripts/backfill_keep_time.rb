#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotent backfill: fix naive datetime strings in DB for multiple sources.
#
# Sources supported:
#   keep     — reads raw JSON files, recomputes from epoch ms + GPS/region TZ
#   strava   — reads raw archive JSON, uses start_date (UTC) + timezone field
#   igpsport — computes offset from start_date (UTC) - start_date_local (naive)
#
# For Strava, the raw archive (data/raw/strava/<id>.json) contains the original
# API response with correct start_date (UTC) and timezone field. The old gem
# stored start_date_local with a wrong "Z" suffix (claiming UTC when it's local
# wall clock), and the DB stripped the marker, leaving naive strings.
#
# This script only writes when the DB value differs. Repeated runs with no
# changes produce zero updates (verified: db-store SHA256 checksums stay identical).
#
# Usage:
#   bundle exec ruby scripts/backfill_keep_time.rb [options]
#
# Options:
#   --db-path PATH       SQLite database path (default: data/db/workouts.db)
#   --source SOURCE      Source to backfill (keep, strava, igpsport; default: keep)
#   --raw-dir DIR        Raw data directory (default: data/raw/<source>)
#   --std-dir DIR        Std data directory (default: data/std/<source>)
#   --dry-run            Report only, do not write to database
#
# Outputs (GitHub Actions):
#   updated=N            Number of rows actually modified

require "json"
require "sequel"
require "optparse"
require "time"

DEFAULT_DB = "data/db/workouts.db"

options = {
  db_path: DEFAULT_DB,
  source: "keep",
  raw_dir: nil,
  std_dir: nil,
  dry_run: false
}

OptionParser.new do |opts|
  opts.on("--db-path PATH") { |v| options[:db_path] = v }
  opts.on("--source SOURCE") { |v| options[:source] = v }
  opts.on("--raw-dir DIR") { |v| options[:raw_dir] = v }
  opts.on("--std-dir DIR") { |v| options[:std_dir] = v }
  opts.on("--dry-run") { options[:dry_run] = true }
end.parse!

options[:raw_dir] ||= "data/raw/#{options[:source]}"
options[:std_dir] ||= "data/std/#{options[:source]}"

VALID_SOURCES = %w[keep strava igpsport].freeze

unless VALID_SOURCES.include?(options[:source])
  warn "backfill: unsupported source '#{options[:source]}'. Supported: #{VALID_SOURCES.join(", ")}"
  exit 1
end

# --- Helpers ---

def load_finder
  require "timezone_finder"
  TimezoneFinder.create
end

def resolve_tz(finder, lat, lng, default_tz)
  tz = finder.timezone_at(lat: lat.to_f, lng: lng.to_f)
  tz = default_tz if tz.nil? || (tz.is_a?(String) && tz.empty?)
  tz
end

# --- Keep helpers ---

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

def compute_keep_targets(raw_data, keep_id, std_dir, finder, default_tz)
  meta = raw_data["meta"]
  start_ms = meta["startTime"]
  return nil unless start_ms

  start_utc = Time.at(start_ms / 1000.0).utc
  target_start_date = start_utc.iso8601

  gps_point = load_std_first_point(std_dir, keep_id)
  region_point = region_coords(raw_data)

  lat, lng = gps_point || region_point
  if lat && lng
    tz_str = resolve_tz(finder, lat, lng, default_tz)
    require "tzinfo"
    tz = TZInfo::Timezone.get(tz_str)
    target_start_date_local = tz.utc_to_local(start_utc).iso8601
  else
    target_start_date_local = start_utc.iso8601
  end

  {start_date: target_start_date, start_date_local: target_start_date_local}
end

# --- Strava helpers (raw archive) ---

def parse_tz_offset(tz_str)
  return nil unless tz_str

  # "(GMT+08:00) Asia/Shanghai" → "+08:00"
  match = tz_str.match(/GMT([+-]\d{2}:\d{2})/)
  return match[1] if match

  nil
end

def compute_strava_targets_from_raw(raw_path)
  return nil unless File.exist?(raw_path)

  raw_data = JSON.parse(File.read(raw_path))
  detail = raw_data["detail"]
  return nil unless detail

  sd = detail["start_date"]
  sdl = detail["start_date_local"]
  tz = detail["timezone"]
  return nil unless sd && sdl && tz

  offset_str = parse_tz_offset(tz)
  return nil unless offset_str

  # start_date is already correct ISO 8601 UTC
  target_start_date = sd

  # start_date_local in raw has wrong "Z" suffix — extract wall clock and
  # reformat with the correct offset from the timezone field.
  wall_clock = sdl.sub(/Z$/, "")
  target_start_date_local = "#{wall_clock}#{offset_str}"

  {start_date: target_start_date, start_date_local: target_start_date_local}
rescue JSON::ParserError
  nil
end

# --- iGPSPORT helpers (offset inference) ---

def parse_utc(sd)
  return nil if sd.nil? || sd.empty?

  clean = sd.strip
  if clean.include?("T")
    Time.parse(clean).utc
  else
    Time.parse(clean + " UTC").utc
  end
rescue ArgumentError
  nil
end

def parse_local(sdl)
  return nil if sdl.nil? || sdl.empty?

  clean = sdl.strip
  Time.parse(clean)
rescue ArgumentError
  nil
end

def infer_offset_hours(utc_time, local_time)
  return nil unless utc_time && local_time

  # Compare wall clock times (not absolute moments).
  # naive start_date_local is a wall clock string; Time.parse treats it as
  # system-local, so we extract h/m/s to compare against the UTC wall clock.
  utc_secs = utc_time.hour * 3600 + utc_time.min * 60 + utc_time.sec
  local_secs = local_time.hour * 3600 + local_time.min * 60 + local_time.sec

  diff = local_secs - utc_secs
  # Handle day wrap (e.g., UTC 23:00, local 07:00 next day → +8h, not -15h)
  diff += 86400 if diff < -43200
  diff -= 86400 if diff > 43200

  hours = diff / 3600.0

  # Validate: offset should be -12..+14 and close to a half-hour boundary
  return nil if hours < -12 || hours > 14
  return nil if (hours * 2 - (hours * 2).round).abs > 0.1

  hours.round(1)
end

def compute_offset_targets(row)
  sd = row[:start_date]
  sdl = row[:start_date_local]

  # Already ISO 8601 with offset? Skip.
  return nil if sdl&.include?("+") && sdl.include?("T")

  utc_time = parse_utc(sd)
  local_time = parse_local(sdl)

  offset = infer_offset_hours(utc_time, local_time)
  return nil unless offset

  # Rebuild start_date as UTC ISO 8601
  target_start_date = utc_time.iso8601

  # Rebuild start_date_local as local ISO 8601 with offset
  offset_str = format("%+03d:00", offset.to_i)
  # For half-hour offsets (e.g., +5.5), format differently
  if offset != offset.to_i
    sign = (offset >= 0) ? "+" : "-"
    h = offset.abs.to_i
    m = ((offset.abs - h) * 60).to_i
    offset_str = format("%s%02d:%02d", sign, h, m)
  end
  target_start_date_local = "#{local_time.strftime("%Y-%m-%dT%H:%M:%S")}#{offset_str}"

  {start_date: target_start_date, start_date_local: target_start_date_local}
end

# --- Main ---

db_path = options[:db_path]
dry_run = options[:dry_run]
source = options[:source]

unless File.exist?(db_path)
  warn "backfill: database not found: #{db_path}"
  exit 1
end

db = Sequel.sqlite(db_path)
db.run("PRAGMA journal_mode=WAL")

rows = db[:activities].where(source: source).all
puts "backfill [#{source}]: #{rows.size} activities in DB"

default_tz = ENV["GIT_FIT_SYSTEM_TIMEZONE"] || "Asia/Shanghai"
finder = (source == "keep") ? load_finder : nil

updated = 0
skipped = 0
errors = 0
raw_missing = 0

rows.each do |row|
  run_id = row[:run_id]
  current_sd = row[:start_date]
  current_sdl = row[:start_date_local]

  targets = case source
  when "keep"
    platform_id = run_id.to_s.sub(/\Akeep_/, "")
    raw_path = File.join(options[:raw_dir], "#{platform_id}.json")
    unless File.exist?(raw_path)
      raw_missing += 1
      next
    end
    raw_data = JSON.parse(File.read(raw_path))
    compute_keep_targets(raw_data, platform_id, options[:std_dir], finder, default_tz)
  when "strava"
    platform_id = run_id.to_s.sub(/\Astrava_/, "")
    raw_path = File.join(options[:raw_dir], "#{platform_id}.json")
    unless File.exist?(raw_path)
      raw_missing += 1
      next
    end
    compute_strava_targets_from_raw(raw_path)
  when "igpsport"
    compute_offset_targets(row)
  end

  unless targets
    skipped += 1
    next
  end

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
    sd_changed = current_sd != targets[:start_date]
    sdl_changed = current_sdl != targets[:start_date_local]
    if sd_changed
      puts "  #{run_id}: sd #{current_sd} -> #{targets[:start_date]}"
    end
    if sdl_changed
      puts "  #{run_id}: sdl #{current_sdl} -> #{targets[:start_date_local]}"
    end
  end
end

db.disconnect

# Summary
puts ""
puts "backfill [#{source}]: done"
puts "  total:   #{rows.size}"
puts "  updated: #{updated}"
puts "  skipped: #{skipped}"
puts "  missing: #{raw_missing}" if source == "keep" || source == "strava"
puts "  errors:  #{errors}"
puts "  dry-run: #{dry_run}" if dry_run

# GitHub Actions output
if ENV["GITHUB_OUTPUT"]
  File.open(ENV["GITHUB_OUTPUT"], "a") do |f|
    f.puts "updated=#{updated}"
  end
end

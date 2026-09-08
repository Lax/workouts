#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotent backfill: populate device / app / lineage for existing activities
# from raw archives (workouts#37). Sources:
#
#   strava        raw/strava/{id}.json      detail.device_name + DEVICE_APP_RULES
#   xingzhe       raw/xingzhe/{id}/detail.json  workout.equipment_info[0].name
#   garmin(_cn)   raw/{source}/{id}/activity.fit (or {id}.fit)  FIT device_info → garminProduct
#   apple_health  raw/apple_health/{short}.xml  Workout sourceName attr
#   others        app from GitFit::DEFAULT_APPS, device nil
#
# git-fit >= 0.26 required (FIT::Decoder.device_info, GitFit.build_lineage).
#
# Usage:
#   bundle exec ruby scripts/backfill_device_app.rb [options]
#
# Options:
#   --db-path PATH   SQLite database path (default: data/db/workouts.db)
#   --raw-dir DIR    Raw data root (default: data/raw)
#   --source SOURCE  Restrict to one source (default: all)
#   --force          Re-run already backfilled rows of the selected source
#                    (e.g. after a device model mapping lands); all+force refused
#   --dry-run        Report only, do not write
#
# Outputs (GitHub Actions):
#   updated=N  Number of rows actually modified

require "json"
require "sequel"
require "optparse"
require "git-fit"
require "git_fit/fit/decoder"
require "git_fit/sync/strava"

DEFAULT_DB = "data/db/workouts.db"
DEFAULT_RAW = "data/raw"

options = {
  db_path: DEFAULT_DB,
  raw_dir: DEFAULT_RAW,
  source: "all",
  force: false,
  dry_run: false
}

OptionParser.new do |opts|
  opts.on("--db-path PATH") { |v| options[:db_path] = v }
  opts.on("--raw-dir DIR") { |v| options[:raw_dir] = v }
  opts.on("--source SOURCE") { |v| options[:source] = v }
  opts.on("--force") { options[:force] = true }
  opts.on("--dry-run") { options[:dry_run] = true }
end.parse!

if options[:force] && options[:source] == "all"
  warn "backfill: --force requires --source (refusing to reset all sources)"
  exit 1
end

unless File.exist?(options[:db_path])
  warn "backfill: database not found: #{options[:db_path]}"
  warn "  Fix: pass --db-path PATH or run from the workouts repo root"
  exit 1
end

db = Sequel.sqlite(options[:db_path])
ds = db[:activities]
ds = if options[:force]
  ds.where(source: options[:source])
elsif options[:source] == "all"
  ds.where(lineage: nil)
else
  ds.where(lineage: nil, source: options[:source])
end

stats = Hash.new(0)
dry_run = options[:dry_run]
raw_dir = options[:raw_dir]
updated = 0

# garmin / garmin_cn: FIT device_info creator message → garminProduct label
garmin_device = lambda do |activity_id, source|
  per_dir = File.join(raw_dir, source, activity_id, "activity.fit")
  fit_path = File.exist?(per_dir) ? per_dir : File.join(raw_dir, source, "#{activity_id}.fit")
  return [nil, nil] unless File.exist?(fit_path)

  infos = GitFit::FIT::Decoder.device_info(fit_path)
  info = infos.find { |d| d["deviceIndex"] == "creator" } || infos.first
  return [nil, nil] unless info && info["garminProduct"]

  [GitFit::Sync::GarminBase.format_garmin_device(info["garminProduct"]), nil]
rescue => e
  warn "backfill: FIT decode failed for #{source}/#{activity_id}: #{e.message}"
  [nil, nil]
end

extractors = {
  "strava" => lambda do |run_id|
    archive = File.join(raw_dir, "strava", "#{run_id.sub("strava_", "")}.json")
    detail = JSON.parse(File.read(archive))["detail"] || {}
    device = detail["device_name"]
    [device, GitFit::Sync::Strava.app_for_device(device)]
  rescue Errno::ENOENT, JSON::ParserError
    [nil, nil] # default_app fallback applies
  end,

  "xingzhe" => lambda do |run_id|
    detail = JSON.parse(File.read(File.join(raw_dir, "xingzhe", run_id.sub("xingzhe_", ""), "detail.json")))
    device = detail.dig("workout", "equipment_info")&.first&.[]("name")
    [device.to_s.empty? ? nil : device, nil]
  rescue Errno::ENOENT, JSON::ParserError
    [nil, nil]
  end,

  "igpsport" => lambda do |run_id|
    fit_path = File.join(raw_dir, "igpsport", "#{run_id.sub("igpsport_", "")}.fit")
    next [nil, nil] unless File.exist?(fit_path)
    infos = GitFit::FIT::Decoder.device_info(fit_path)
    info = infos.find { |d| d["deviceIndex"] == "creator" } || infos.first
    model = info && GitFit::Sync::IGPSPORT::FIT_PRODUCT_MODELS[info["product"]]
    [model ? "iGPSPORT #{model}" : nil, nil]
  rescue => e
    warn "backfill: igpsport FIT decode failed for #{run_id}: #{e.message}"
    [nil, nil]
  end,

  "garmin" => lambda do |run_id|
    garmin_device.call(run_id.sub("garmin_", ""), "garmin")
  end,

  "garmin_cn" => lambda do |run_id|
    garmin_device.call(run_id.sub("garmin_cn_", ""), "garmin_cn")
  end,

  "apple_health" => lambda do |run_id|
    xml = File.read(File.join(raw_dir, "apple_health", "#{run_id.sub("apple_health_", "")}.xml"))
    source_name = xml.match(/sourceName="([^"]*)"/)&.captures&.first
    [nil, source_name]
  rescue Errno::ENOENT
    [nil, nil]
  end
}

ds.each do |row|
  source = row[:source]
  device, app = extractors.key?(source) ? extractors[source].call(row[:run_id]) : [nil, nil]
  app = GitFit.default_app(app, source)
  lineage = GitFit.build_lineage(device, app, source)
  next if row[:lineage] == lineage

  stats[source] += 1
  if dry_run
    puts "[dry-run] #{row[:run_id]}: device=#{device.inspect} app=#{app.inspect} lineage=#{lineage.inspect}"
    next
  end
  db[:activities].where(id: row[:id]).update(device: device, app: app, lineage: lineage)
  updated += 1
end

action = dry_run ? "would update" : "updated"
puts "#{action}=#{dry_run ? stats.values.sum : updated} (#{stats.map { |s, n| "#{s}:#{n}" }.join(" ")})"

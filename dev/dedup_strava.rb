#!/usr/bin/env ruby
require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "workouts"
require "json"
require "time"

db = Sequel.sqlite("data/workouts.db")
DUPLICATE_SOURCES = %w[keep xingzhe xoss igpsport garmin garmin_cn].freeze

strava = db[:activities].where(source: "strava").all
updated = 0

strava.each do |s|
  next unless s[:distance] && s[:distance] > 100

  candidates = db[:activities]
    .where(source: DUPLICATE_SOURCES, sport_category: s[:sport_category])
    .exclude(distance: nil)
    .all

  best = nil
  best_conf = 0.0

  candidates.each do |c|
    t_diff = begin
      (Time.parse(s[:start_date].to_s) - Time.parse(c[:start_date].to_s)).abs
    rescue
      9999
    end
    next if t_diff > 300

    max_dist = [s[:distance], c[:distance] || 0].max
    d_diff = (s[:distance] - (c[:distance] || 0)).abs
    next if max_dist == 0 || d_diff > max_dist * 0.15

    max_dur = [s[:moving_time] || 0, c[:moving_time] || 0].max
    dur_diff = ((s[:moving_time] || 0) - (c[:moving_time] || 0)).abs

    t_score = [1.0 - t_diff / 300.0, 0.0].max
    d_score = (max_dist > 0) ? [1.0 - d_diff / (max_dist * 0.15), 0.0].max : 0.0
    dur_score = (max_dur > 0 && dur_diff <= max_dur * 0.15) ? [1.0 - dur_diff / (max_dur * 0.15), 0.0].max : 0.0
    conf = (t_score * 0.4 + d_score * 0.4 + dur_score * 0.2).round(4)

    if conf > best_conf
      best_conf = conf
      best = {source: c[:source], run_id: c[:run_id], confidence: conf, primary_distance: c[:distance]}
    end
  end

  if best && best_conf >= 0.15
    best[:flag] = (best_conf >= 0.85) ? "derived" : "overlap"
    dup_json = JSON.generate([best])
    db[:activities].where(run_id: s[:run_id]).update(duplicate_info: dup_json)
    puts "#{s[:run_id]}: flag=#{best[:flag]} conf=#{best_conf} → #{best[:source]} #{best[:run_id]}"
    updated += 1
  end
end

puts "\nUpdated #{updated} activities with duplicate_info"

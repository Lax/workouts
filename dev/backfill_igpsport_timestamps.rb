#!/usr/bin/env ruby
require_relative "../lib/workouts"
require "sequel"

FIT_EPOCH = Time.new(1989, 12, 31, 0, 0, 0, "+00:00").to_i
db = Sequel.sqlite("data/workouts.db")
count = 0
errors = 0

db[:activities].where(source: "igpsport").each do |row|
  ride_id = row[:run_id].sub("igpsport_", "")
  fit_path = File.join("data", "raw", "igpsport", "#{ride_id}.fit")
  unless File.exist?(fit_path)
    warn "missing #{fit_path}"
    errors += 1
    next
  end

  begin
    points = Workouts::FIT::Decoder.decode(fit_path)
    first_ts = if points.any?
      points.first["timestamp"]
    else
      Workouts::FIT::Decoder.first_timestamp(fit_path)
    end

    unless first_ts
      warn "skip #{ride_id}: empty FIT or no timestamp"
      next
    end

    t = Time.at(FIT_EPOCH + first_ts)
    utc = t.utc.strftime("%Y-%m-%d %H:%M:%S")
    local = t.getlocal("+08:00").strftime("%Y-%m-%d %H:%M:%S")

    db[:activities].where(run_id: row[:run_id]).update(
      start_date: utc,
      start_date_local: local
    )
    count += 1
    puts "#{row[:run_id]}: #{row[:start_date]} -> UTC=#{utc} CST=#{local}"
  rescue => e
    warn "error #{ride_id}: #{e}"
    errors += 1
  end
end

puts "Updated #{count} records, #{errors} errors"

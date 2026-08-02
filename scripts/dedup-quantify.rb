#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "sequel"
require "time"

default_db = ENV.fetch("GIT_FIT_DATABASE_PATH", "data/db/workouts.db")
options = {db: default_db}
OptionParser.new do |opts|
  opts.on("--db PATH", "Database path (default: $GIT_FIT_DATABASE_PATH or #{default_db})") { |v| options[:db] = v }
  opts.on("-h", "--help", "Print help") {
    puts opts
    exit
  }
end.parse!

db = Sequel.sqlite(options[:db])
activities = db[:activities].where(Sequel.lit("distance > 100")).order(:start_date).all

sources = activities.map { |a| a[:source] }.uniq.sort
puts "=" * 60
puts "CROSS-SOURCE DUPLICATE QUANTIFICATION REPORT"
puts "Generated: #{Time.now.utc.iso8601}"
puts "Database: #{options[:db]}"
puts "Activities (dist>100m): #{activities.size}"
puts "Sources: #{sources.join(", ")}"
puts "=" * 60

# Section 1: Overlap Matrix
puts "\n1. OVERLAP MATRIX (same date + time<5s + dist<1%)"
puts "   Diagonal = total per source, off-diagonal = precision duplicate pairs"
puts ""

by_date = activities.group_by { |a|
  begin
    Time.parse(a[:start_date]).to_date
  rescue
    nil
  end
}
by_date.delete(nil)

source_total = Hash.new(0)
activities.each { |a| source_total[a[:source]] += 1 }

matrix = Hash.new { |h, k| h[k] = Hash.new(0) }
by_date.each_value do |day_acts|
  day_acts.each_with_index do |a, i|
    (i + 1...day_acts.size).each do |j|
      b = day_acts[j]
      next if a[:source] == b[:source]

      t_a = begin
        Time.parse(a[:start_date])
      rescue
        nil
      end
      t_b = begin
        Time.parse(b[:start_date])
      rescue
        nil
      end
      next unless t_a && t_b
      next unless (t_a - t_b).abs < 5

      d_a = a[:distance].to_f
      d_b = b[:distance].to_f
      next unless d_a > 0 && d_b > 0
      next unless (d_a - d_b).abs / [d_a, d_b].max < 0.01

      matrix[a[:source]][b[:source]] += 1
    end
  end
end

header = sources.map { |s| s[0..5].ljust(6) }.join(" ")
puts " " * 8 + header
sources.each do |s|
  row = sources.map do |s2|
    val = (s == s2) ? source_total[s] : matrix[s][s2]
    val.to_s.ljust(6)
  end.join(" ")
  puts "#{s.ljust(8)}#{row}"
end

# Section 2: Field Completeness
puts "\n2. FIELD COMPLETENESS BY SOURCE"
puts "   % of activities with non-null values"
puts ""

fields = %i[average_heartrate average_power average_cadence average_temperature elevation_gain]
puts "Source        #{fields.map { |f| f.to_s[0..11].ljust(12) }.join(" ")}"
sources.each do |src|
  src_acts = activities.select { |a| a[:source] == src }
  next if src_acts.empty?
  row = fields.map do |f|
    pct = (src_acts.count { |a| a[f] } * 100.0 / src_acts.size).round
    "#{pct}%".ljust(12)
  end.join(" ")
  puts "#{src.ljust(12)} #{row}"
end

# Section 3: Dedup Group Stats
puts "\n3. DEDUP GROUP STATS"
if db.table_exists?(:dedup_groups)
  group_count = db[:dedup_groups].count
  member_count = db[:dedup_group_members].count
  flag_dist = db[:dedup_group_members].group_and_count(:flag).all
  puts "   Groups: #{group_count}"
  puts "   Members: #{member_count}"
  puts "   Avg members/group: #{(member_count.to_f / [group_count, 1].max).round(1)}"
  puts "   Flag distribution:"
  flag_dist.each { |r| puts "     #{r[:flag]}: #{r[:count]}" }
else
  puts "   (dedup_groups table not found - run migration 008)"
end

puts ""
puts "=" * 60

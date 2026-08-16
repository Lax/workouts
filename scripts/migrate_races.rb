#!/usr/bin/env ruby
# frozen_string_literal: true

# 一次性迁移：newbie.run 赛事数据 → data/events/races.json
#
# 读取 newbie.run/_data/people/lax/races.yml（个人参赛列表）+
# _data/races/{YYYY}/{YYYY-MM}/{slug}.yml（赛事定义），按需整合 + 格式转换，
# 输出扁平 JSON（本地方便使用的格式，不完全照搬源结构）。
#
# 用法:
#   ruby scripts/migrate_races.rb [--source <newbie.run路径>] [--output <输出路径>]
#
# 默认: --source ../newbie.run  --output data/events/races.json
# 产物 check-in 入 git；gh-pages 构建仅 cp 到 site/（无 newbie.run 运行时依赖）。

require "yaml"
require "json"
require "date"
require "fileutils"
require "optparse"

options = {
  source: "../newbie.run",
  output: "data/events/races.json"
}

OptionParser.new do |opts|
  opts.on("--source DIR", "newbie.run checkout 路径") { |v| options[:source] = v }
  opts.on("--output PATH", "输出路径") { |v| options[:output] = v }
end.parse!

def load_personal_races(source)
  candidates = [
    File.join(source, "_data/people/lax/races.yml"),
    File.join(source, "_data/people/lax/results.yml")
  ]
  path = candidates.find { |f| File.exist?(f) }
  return nil unless path

  list = YAML.safe_load_file(path)
  list.is_a?(Array) ? list : nil
end

def load_race_definition(source, slug)
  dir = File.join(source, "_data/races")
  return nil unless File.directory?(dir)

  match = Dir.glob(File.join(dir, "*", "*", "#{slug}.yml")).first
  return nil unless match

  YAML.safe_load_file(match)
end

def parse_race_date(value)
  Date.parse(value.to_s).strftime("%Y-%m-%d")
rescue ArgumentError
  nil
end

personal = load_personal_races(options[:source])
if personal.nil? || personal.empty?
  warn "migrate_races: 未找到 races.yml 且列表为空，检查 --source: #{options[:source]}"
  exit 1
end

events = personal.filter_map do |entry|
  slug = entry["race"].to_s
  next nil if slug.empty?

  defn = load_race_definition(options[:source], slug)
  date = defn ? parse_race_date(defn["date"]) : nil

  event = {"id" => slug, "name" => (defn && defn["name"]) || slug}
  event["date"] = date if date
  event["place"] = defn["place"] if defn && defn["place"]
  if defn && defn["categories"].is_a?(Array) && !defn["categories"].empty?
    event["categories"] = defn["categories"].map do |c|
      cat = {"name" => c["name"].to_s}
      cat["itra"] = c["itra"] if c["itra"]
      cat["start"] = c["start"].to_s if c["start"]
      cat["cutoff"] = c["cutoff"].to_s if c["cutoff"]
      cat
    end
  end
  if entry["category"] || entry["status"]
    result = {}
    result["category"] = entry["category"].to_s if entry["category"]
    result["status"] = entry["status"].to_s if entry["status"]
    result["time"] = entry["time"].to_s if entry["time"]
    event["result"] = result
  end
  event["links"] = defn["links"] if defn && defn["links"].is_a?(Array) && !defn["links"].empty?
  event
end

events.sort_by! { |e| e["date"] || "" }

FileUtils.mkdir_p(File.dirname(options[:output]))
File.write(options[:output], JSON.pretty_generate({"events" => events}))
puts "migrate_races: #{events.size} events -> #{options[:output]}"

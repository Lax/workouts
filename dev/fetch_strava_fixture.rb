#!/usr/bin/env ruby
require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "yaml"
require "json"
require "faraday"

config_path = File.expand_path("../config/config.yml", __dir__)
raw = YAML.safe_load_file(config_path)
cfg = raw.dig("sync", "strava")
abort "Strava credentials not found" unless cfg["client_id"] && cfg["client_secret"] && cfg["refresh_token"]

# Refresh token
puts "Refreshing token..."
resp = Faraday.post("https://www.strava.com/oauth/token") do |r|
  r.body = {client_id: cfg["client_id"], client_secret: cfg["client_secret"],
             refresh_token: cfg["refresh_token"], grant_type: "refresh_token"}
end
abort "Token refresh failed: #{resp.status}" unless resp.success?
token = JSON.parse(resp.body)["access_token"]
puts "Token OK"

# Pick 3 activities: long, medium, short
activity_ids = %w[3103806497 2983295413 13695388943]
fixtures_dir = File.expand_path("../spec/fixtures/strava", __dir__)
Dir.mkdir(fixtures_dir) unless Dir.exist?(fixtures_dir)

activity_ids.each do |id|
  puts "\n=== Activity #{id} ==="

  # Detail API
  resp = Faraday.get("https://www.strava.com/api/v3/activities/#{id}") do |r|
    r.headers["Authorization"] = "Bearer #{token}"
  end
  if resp.success?
    detail = JSON.parse(resp.body)
    File.write(File.join(fixtures_dir, "#{id}.json"), JSON.pretty_generate(detail))
    type = detail["sport_type"] || detail["type"]
    dist = detail["distance"]&.round(1)
    puts "  detail: #{type}, #{dist}m, start=#{detail["start_date"]}"
  else
    puts "  detail FAILED: HTTP #{resp.status}"
    next
  end

  # Streams API (truncate to first 10 for fixture)
  stream_keys = %w[lat_lng altitude time heartrate cadence watts temp velocity_smooth]
  resp = Faraday.get("https://www.strava.com/api/v3/activities/#{id}/streams") do |r|
    r.headers["Authorization"] = "Bearer #{token}"
    r.params = {keys: stream_keys.join(","), key_by_type: true}
  end
  if resp.success?
    streams = JSON.parse(resp.body)
    truncated = {}
    streams.each { |k, v| truncated[k] = v.is_a?(Hash) ? v.merge("data" => v["data"].first(10)) : v }
    File.write(File.join(fixtures_dir, "streams_#{id}.json"), JSON.pretty_generate(truncated))
    sizes = streams.map { |k, v| "#{k}:#{v["data"].size}" }.join(", ")
    puts "  streams: #{sizes} → truncated to 10"
  else
    puts "  streams FAILED: HTTP #{resp.status}"
  end

  sleep 1
end

puts "\nDone! Fixtures in #{fixtures_dir}"

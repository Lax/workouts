#!/usr/bin/env ruby
require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "workouts"
require "yaml"
require "json"
require "faraday"

config_path = File.expand_path("../config/config.yml", __dir__)
raw = YAML.safe_load(File.read(config_path))
cfg = raw.dig("sync", "igpsport")
phone = cfg["phone"]
password = cfg["password"]

unless phone && password
  abort "iGPSPORT credentials not found in config/config.yml"
end

# Login
puts "Logging in..."
resp = Faraday.post("https://prod.zh.igpsport.com/service/auth/account/login",
  JSON.generate({ appId: "igpsport-web", username: phone, password: password }),
  { "Content-Type" => "application/json" }
)
abort "Login failed: #{resp.status}" unless resp.status == 200
data = JSON.parse(resp.body)
token = data.dig("data", "access_token") || abort("No access_token in response")
puts "Login OK, token: #{token[0..20]}..."

# Save login response
fixtures_dir = File.expand_path("../spec/fixtures/igpsport", __dir__)
Dir.mkdir(fixtures_dir) unless Dir.exist?(fixtures_dir)
File.write(File.join(fixtures_dir, "login_response.json"), JSON.pretty_generate(data))
puts "Wrote login_response.json"

# Fetch first page of activities
puts "Fetching activities..."
headers = { "Authorization" => "Bearer #{token}" }
resp = Faraday.get(
  "https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/queryMyActivity",
  { pageNo: 1, pageSize: 20, sort: 1, reqType: 0 },
  headers
)
abort "Fetch failed: #{resp.status}" unless resp.status == 200
body = JSON.parse(resp.body)
rows = body.dig("data", "rows") || []
puts "Found #{rows.size} activities"

# Truncate to first 3 for fixture
truncated = rows.first(3)
File.write(File.join(fixtures_dir, "activities_page.json"),
  JSON.pretty_generate({ "data" => { "rows" => truncated } }))
puts "Wrote activities_page.json (#{truncated.size} activities)"

truncated.each do |act|
  puts "  rideId=#{act["rideId"]}, type=#{act["exerciseType"]}, dist=#{act["rideDistance"]}, start=#{act["startTime"]}"
end

puts "\nDone!"

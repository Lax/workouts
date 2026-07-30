#!/usr/bin/env ruby
require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "yaml"
require "json"
require "faraday"

config_path = File.expand_path("../config/config.yml", __dir__)
raw = YAML.safe_load_file(config_path)
cfg = raw.dig("sync", "igpsport")
abort "iGPSPORT credentials not found" unless cfg["phone"] && cfg["password"]

puts "Logging in..."
resp = Faraday.post("https://prod.zh.igpsport.com/service/auth/account/login",
  JSON.generate({appId: "igpsport-web", username: cfg["phone"], password: cfg["password"]}),
  {"Content-Type" => "application/json"})
abort "Login failed: #{resp.status}" unless resp.status == 200
token = JSON.parse(resp.body).dig("data", "access_token") || abort("No token")
auth = {"Authorization" => "Bearer #{token}"}
puts "Login OK\n\n"

# Check activity list with different reqType values
{"FIT(0)" => 0, "GPX(1)" => 1, "TCX(2)" => 2}.each do |label, rt|
  resp = Faraday.get(
    "https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/queryMyActivity",
    {pageNo: 1, pageSize: 5, sort: 1, reqType: rt},
    auth
  )
  if resp.status == 200
    data = JSON.parse(resp.body)
    rows = data.dig("data", "rows") || []
    puts "reqType=#{rt} (#{label}): #{rows.size} activities"
    ride_ids = rows.map { |r| r["rideId"] }
    puts "  rideIds: #{ride_ids.join(", ")}"
  else
    puts "reqType=#{rt} (#{label}): HTTP #{resp.status}"
  end
end

# Check download URL for FIT format
puts "\n=== Checking FIT download (from reqType=0) ==="
ride_id = 44083595
resp = Faraday.get("https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/queryMyActivity",
  {pageNo: 1, pageSize: 20, sort: 1, reqType: 0}, auth)
rows = JSON.parse(resp.body).dig("data", "rows") || []
fit_ride = rows.find { |r| r["rideId"] == ride_id } || rows.first
ride_id = fit_ride["rideId"]

puts "Using rideId=#{ride_id}"
url = "https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/getDownloadUrl/#{ride_id}"
resp = Faraday.get(url, {}, auth)
if resp.status == 200
  file_url = JSON.parse(resp.body)["data"]
  puts "FIT URL: #{file_url}"
  fit_data = Faraday.get(file_url).body
  fit_size = fit_data.bytesize
  puts "FIT size: #{fit_size} bytes"
  sig_offset = fit_data.index(".FIT")
  puts "FIT signature at offset: #{sig_offset}" if sig_offset
  File.write("/tmp/igpsport_fit_sample.#{ride_id}.fit", fit_data)
  puts "Saved: /tmp/igpsport_fit_sample.#{ride_id}.fit"
end

# Check download URL for GPX format (reqType=1)
puts "\n=== Checking GPX download (from reqType=1) ==="
resp = Faraday.get("https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/queryMyActivity",
  {pageNo: 1, pageSize: 20, sort: 1, reqType: 1}, auth)
rows = JSON.parse(resp.body).dig("data", "rows") || []
if rows.any?
  gpx_ride = rows.first
  gid = gpx_ride["rideId"]
  puts "GPX available for rideId=#{gid}"
  url = "https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/getDownloadUrl/#{gid}"
  resp = Faraday.get(url, {}, auth)
  if resp.status == 200
    file_url = JSON.parse(resp.body)["data"]
    puts "GPX URL: #{file_url}"
    gpx_data = Faraday.get(file_url).body
    puts "GPX size: #{gpx_data.bytesize} bytes"
    puts "First 200 chars: #{gpx_data[0..200].inspect}"
    if gpx_data.start_with?("<?xml")
      puts "FORMAT: GPX (XML)"
      File.write("/tmp/igpsport_gpx_sample.#{gid}.gpx", gpx_data)
      puts "Saved: /tmp/igpsport_gpx_sample.#{gid}.gpx"
    else
      puts "FORMAT: NOT GPX (unexpected)"
    end
  end
else
  puts "No GPX-format activities found (reqType=1 returns empty)"
end

# Check TCX format
puts "\n=== Checking TCX download (from reqType=2) ==="
resp = Faraday.get("https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/queryMyActivity",
  {pageNo: 1, pageSize: 20, sort: 1, reqType: 2}, auth)
rows = JSON.parse(resp.body).dig("data", "rows") || []
puts "TCX available activities: #{rows.size}"

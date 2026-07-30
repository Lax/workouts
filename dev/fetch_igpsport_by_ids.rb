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

# Login
puts "Logging in..."
resp = Faraday.post("https://prod.zh.igpsport.com/service/auth/account/login",
  JSON.generate({appId: "igpsport-web", username: cfg["phone"], password: cfg["password"]}),
  {"Content-Type" => "application/json"})
abort "Login failed: #{resp.status}" unless resp.status == 200
token = JSON.parse(resp.body).dig("data", "access_token") || abort("No token")
auth_headers = {"Authorization" => "Bearer #{token}"}
puts "Login OK"

# Target rideIds
target_ids = [44083595, 44854056]
found = {}
page = 1

loop do
  print "\rSearching page #{page}..."
  resp = Faraday.get(
    "https://prod.zh.igpsport.com/service/web-gateway/web-analyze/activity/queryMyActivity",
    {pageNo: page, pageSize: 20, sort: 1, reqType: 0},
    auth_headers
  )
  break unless resp.status == 200

  rows = JSON.parse(resp.body).dig("data", "rows") || []
  break if rows.empty?

  rows.each do |row|
    rid = row["rideId"]
    if target_ids.include?(rid)
      found[rid] = row
      puts "\nFound rideId=#{rid}, date=#{row["startTime"]}, dist=#{row["rideDistance"]}"
    end
  end

  break if found.size == target_ids.size
  page += 1
  sleep 0.3
end

puts "\nSearch complete. Found #{found.size}/#{target_ids.size} targets."

missing = target_ids - found.keys
if missing.any?
  puts "WARNING: Not found: #{missing.join(", ")}. They will be omitted."
end

# Keep the best record (50279925, 2341m), replace the other two
fixtures_dir = File.expand_path("../spec/fixtures/igpsport", __dir__)
current_path = File.join(fixtures_dir, "activities_page.json")
current = JSON.parse(File.read(current_path))
all_rows = current.dig("data", "rows")

keep_row = all_rows.find { |r| r["rideId"] == 50279925 }

new_rows = [keep_row]
found.each_value { |row| new_rows << row if row["rideId"] != keep_row&.dig("rideId") }

output = {"data" => {"rows" => new_rows}}
File.write(current_path, JSON.pretty_generate(output))
puts "\nUpdated fixture: #{new_rows.size} rows"
new_rows.each { |r| puts "  rideId=#{r["rideId"]}, dist=#{r["rideDistance"]}, date=#{r["startTime"]}" }
puts "Done!"

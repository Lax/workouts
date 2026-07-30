#!/usr/bin/env ruby
# Fetch real Keep activity data to generate test fixtures
require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "workouts"
require "yaml"
require "json"
require "base64"
require "net/http"
require "uri"

config_path = File.expand_path("../config/config.yml", __dir__)
raw = YAML.safe_load_file(config_path)
cfg = raw.dig("sync", "keep")
phone = cfg["phone"] || cfg["mobile"]
password = cfg["password"]

unless phone && password
  abort "Keep credentials not found in config/config.yml"
end

headers = {
  "User-Agent" => "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:78.0) Gecko/20100101 Firefox/78.0",
  "Content-Type" => "application/x-www-form-urlencoded;charset=utf-8"
}

def http_post(url, body, headers)
  uri = URI(url)
  req = Net::HTTP::Post.new(uri)
  headers.each { |k, v| req[k] = v }
  req.body = body.is_a?(Hash) ? URI.encode_www_form(body) : body
  http = Net::HTTP.new(uri.host, uri.port, nil, nil, nil, nil)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 30
  http.read_timeout = 60
  http.start { |h| h.request(req) }
end

def http_get(url, headers)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  headers.each { |k, v| req[k] = v }
  http = Net::HTTP.new(uri.host, uri.port, nil, nil, nil, nil)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 30
  http.read_timeout = 60
  http.start { |h| h.request(req) }
end

# Login
puts "Logging in..."
resp = http_post("https://api.gotokeep.com/v1.1/users/login", {mobile: phone, password: password}, headers)
raise "Login failed: #{resp.code}" unless resp.code.to_i == 200
data = JSON.parse(resp.body)
token = data.dig("data", "token") || abort("No token in login response")
headers["Authorization"] = "Bearer #{token}"
puts "Login OK"

# Fetch running stats to get activity IDs
puts "Fetching running stats..."
resp = http_get("https://api.gotokeep.com/pd/v3/stats/detail?dateUnit=all&type=running&lastDate=0", headers)
raise "Stats failed: #{resp.code}" unless resp.code.to_i == 200
stats = JSON.parse(resp.body)

# Find a running activity with GPS data (has geoPoints)
record = stats.dig("data", "records")&.first
abort "No records found" unless record
logs = record["logs"] || []
puts "Found #{logs.size} running activities, fetching first detailed log..."

# Get the first non-doubtful activity
compound_id = nil
logs.each do |log|
  s = log["stats"] || log
  next if s["isDoubtful"]
  compound_id = s["id"]
  break
end
abort "No suitable activity found" unless compound_id
puts "Using activity: #{compound_id}"

# Fetch detailed log
resp = http_get("https://api.gotokeep.com/pd/v3/runninglog/#{compound_id}", headers)
raise "Log failed: #{resp.code}" unless resp.code.to_i == 200
activity = JSON.parse(resp.body)
run_data = activity["data"]
abort "No run_data" unless run_data

puts "Activity: #{run_data["dataType"]} #{run_data["startTime"]}"

# Extract encrypted fields
geo_points_raw = run_data["geoPoints"]
hr_raw = run_data.dig("heartRate", "heartRates")
puts "geoPoints present: #{!geo_points_raw.nil?} (#{geo_points_raw&.length} chars)"
puts "heartRates present: #{!hr_raw.nil?} (#{hr_raw&.length} chars)"

# Truncate to first 10 GPS points for fixture size
# Need to decode, truncate, re-encode
AES_KEY = Base64.decode64("NTZmZTU5OzgyZzpkODczYw==")
AES_IV = Base64.decode64("MjM0Njg5MjQzMjkyMDMwMA==")

def decrypt(encrypted_b64)
  raw = Base64.decode64(encrypted_b64)
  cipher = OpenSSL::Cipher.new("AES-128-CBC")
  cipher.decrypt
  cipher.key = AES_KEY
  cipher.iv = AES_IV
  decrypted = cipher.update(raw) + cipher.final
  inflate(decrypted)
end

def inflate(data)
  [-Zlib::MAX_WBITS, Zlib::MAX_WBITS, Zlib::MAX_WBITS + 16].each do |wbits|
    inflater = Zlib::Inflate.new(wbits)
    result = inflater.inflate(data)
    begin
      inflater.finish
    rescue
      nil
    end
    inflater.close
    return result
  rescue Zlib::DataError
    next
  end
  raise Zlib::DataError, "cannot inflate data"
end

def encrypt_and_encode(plaintext)
  deflated = Zlib::Deflate.deflate(plaintext)
  cipher = OpenSSL::Cipher.new("AES-128-CBC")
  cipher.encrypt
  cipher.key = AES_KEY
  cipher.iv = AES_IV
  encrypted = cipher.update(deflated) + cipher.final
  Base64.strict_encode64(encrypted)
end

def encode_only(plaintext)
  deflated = Zlib::Deflate.deflate(plaintext)
  Base64.strict_encode64(deflated)
end

fixtures_dir = File.expand_path("../spec/fixtures/keep", __dir__)
Dir.mkdir(fixtures_dir) unless Dir.exist?(fixtures_dir)

# Truncate geo points to first 10 for manageable fixture
if geo_points_raw
  decrypted_geo = JSON.parse(decrypt(geo_points_raw))
  truncated = decrypted_geo.first(10)
  puts "Truncated geo from #{decrypted_geo.size} to #{truncated.size} points"
  re_encrypted = encrypt_and_encode(JSON.generate(truncated))
  File.write(File.join(fixtures_dir, "encrypted_geo.txt"), re_encrypted)
  File.write(File.join(fixtures_dir, "geo_plain.json"), JSON.pretty_generate(truncated))
  puts "Wrote: encrypted_geo.txt (#{re_encrypted.length} chars), geo_plain.json"
end

# Truncate HR data to first 5
if hr_raw && !hr_raw.empty?
  decrypted_hr = JSON.parse(inflate(Base64.decode64(hr_raw)))
  truncated_hr = decrypted_hr.first(5)
  puts "Truncated HR from #{decrypted_hr.size} to #{truncated_hr.size} points"
  re_encoded = encode_only(JSON.generate(truncated_hr))
  File.write(File.join(fixtures_dir, "encrypted_hr.txt"), re_encoded)
  File.write(File.join(fixtures_dir, "hr_plain.json"), JSON.pretty_generate(truncated_hr))
  puts "Wrote: encrypted_hr.txt (#{re_encoded.length} chars), hr_plain.json"
else
  puts "No HR data available, creating empty fixture"
  File.write(File.join(fixtures_dir, "encrypted_hr.txt"), "")
  File.write(File.join(fixtures_dir, "hr_plain.json"), "[]")
end

# Extract run_data metadata (strip large encrypted fields)
run_data_fixture = run_data.dup
run_data_fixture.delete("geoPoints")
run_data_fixture.delete("heartRate")
File.write(File.join(fixtures_dir, "run_data.json"), JSON.pretty_generate(run_data_fixture))
puts "Wrote: run_data.json"

puts "\nDone! Fixtures written to #{fixtures_dir}"

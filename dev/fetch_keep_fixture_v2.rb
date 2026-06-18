#!/usr/bin/env ruby
# Fetch improved Keep fixture: long distance, with HR data
require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "workouts"
require "yaml"
require "json"
require "base64"
require "net/http"
require "uri"

config_path = File.expand_path("../config/config.yml", __dir__)
raw = YAML.safe_load(File.read(config_path))
cfg = raw.dig("sync", "keep")
phone = cfg["phone"] || cfg["mobile"]
password = cfg["password"]
abort "Keep credentials not found" unless phone && password

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
    begin
      inflater = Zlib::Inflate.new(wbits)
      result = inflater.inflate(data)
      inflater.finish rescue nil
      inflater.close
      return result
    rescue Zlib::DataError
      next
    end
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

# Login
puts "Logging in..."
headers = {
  "User-Agent" => "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:78.0) Gecko/20100101 Firefox/78.0",
  "Content-Type" => "application/x-www-form-urlencoded;charset=utf-8"
}
resp = http_post("https://api.gotokeep.com/v1.1/users/login", { mobile: phone, password: password }, headers)
raise "Login failed: #{resp.code}" unless resp.code.to_i == 200
data = JSON.parse(resp.body)
token = data.dig("data", "token") || abort("No token")
headers["Authorization"] = "Bearer #{token}"
puts "Login OK"

# Candidate numeric IDs with HR data (from DB query)
# Distance, HR, Date
candidates = [
  { id: "9223370454411659807", dist: 25024, hr: 76,  date: "2020-02-23", sport: "running" },
  { id: "9223370458896850307", dist: 18809, hr: 158, date: "2020-01-02", sport: "running" },
]

fixtures_dir = File.expand_path("../spec/fixtures/keep", __dir__)

candidates.each do |cand|
  compound_id = "57b479009962c35607c65348_#{cand[:id]}_rn"
  sport = cand[:sport]
  puts "\nTrying: #{compound_id} (#{cand[:dist]}m, HR#{cand[:hr]})"

  resp = http_get("https://api.gotokeep.com/pd/v3/#{sport}log/#{compound_id}", headers)
  if resp.code.to_i != 200
    puts "  HTTP #{resp.code}, skip"
    next
  end

  activity = JSON.parse(resp.body)
  run_data = activity["data"]
  next unless run_data

  geo_points_raw = run_data["geoPoints"]
  hr_raw = run_data.dig("heartRate", "heartRates")
  distance = run_data["distance"]

  puts "  distance: #{distance}, geo: #{geo_points_raw&.length} chars, hr: #{hr_raw&.length} chars"

  next unless geo_points_raw && geo_points_raw.length > 100
  next unless hr_raw && hr_raw.length > 10

  puts "  ✓ Has both GPS and HR data. Generating fixtures..."

  # Decrypt geo
  decrypted_geo = JSON.parse(decrypt(geo_points_raw))

  # Decrypt HR
  decrypted_hr = JSON.parse(inflate(Base64.decode64(hr_raw)))

  puts "  Geo points: #{decrypted_geo.size}, HR entries: #{decrypted_hr.size}"

  # Truncate to 10 geo points, 5 HR entries
  truncated_geo = decrypted_geo.first(10)
  truncated_hr = decrypted_hr.first(5)

  File.write(File.join(fixtures_dir, "encrypted_geo.txt"), encrypt_and_encode(JSON.generate(truncated_geo)))
  File.write(File.join(fixtures_dir, "geo_plain.json"), JSON.pretty_generate(truncated_geo))
  File.write(File.join(fixtures_dir, "encrypted_hr.txt"), encode_only(JSON.generate(truncated_hr)))
  File.write(File.join(fixtures_dir, "hr_plain.json"), JSON.pretty_generate(truncated_hr))

  # Write run_data without large encrypted fields
  run_data_fixture = run_data.dup
  run_data_fixture.delete("geoPoints")
  run_data_fixture.delete("heartRate")
  File.write(File.join(fixtures_dir, "run_data.json"), JSON.pretty_generate(run_data_fixture))

  puts "  ✓ Fixtures written to #{fixtures_dir}"
  puts "\nDone!"
  exit 0
end

puts "\nNo suitable activities found among candidates"
exit 1

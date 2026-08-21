#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetch Keep API raw (encrypted) + decrypted data for run_id 9223370467197600022
# Usage: ruby scripts/fetch_keep_raw_9223370467197600022.rb [--phone PHONE] [--password PASS]
#   defaults from config.yml sync.keep.phone/password or GIT_FIT_KEEP_* env
# Outputs:
#   ./tmp/keep_9223370467197600022_raw.json        # HTTP response body (未解密原始格式)
#   ./tmp/keep_9223370467197600022_decrypted.json  # decoded geoPoints + hrData + meta
#   ./tmp/keep_9223370467197600022_payload.json    # wrapper for inspection

require "json"
require "net/http"
require "uri"
require "base64"
require "openssl"
require "zlib"
require "yaml"
require "fileutils"
require "optparse"

RUN_ID = "9223370467197600022"
SPORTS = %w[running hiking cycling].freeze  # KEEP_TYPES order

LOGIN_URL = "https://api.gotokeep.com/v1.1/users/login"
LOG_URL_TMPL = "https://api.gotokeep.com/pd/v3/%{sport}log/%{compound_id}"

# Keep AES material (from git-fit/lib/git_fit/source/keep.rb)
AES_KEY = Base64.decode64("NTZmZTU5OzgyZzpkODczYw==")
AES_IV = Base64.decode64("MjM0Njg5MjQzMjkyMDMwMA==")

options = {}
OptionParser.new do |o|
  o.on("--phone PHONE") { |v| options[:phone] = v }
  o.on("--password PASS") { |v| options[:password] = v }
  o.on("--compound ID") { |v| options[:compound] = v }
  o.on("--out DIR") { |v| options[:out] = v }
end.parse!(ARGV)

def load_config
  env_phone = ENV["GIT_FIT_KEEP_PHONE"]
  env_pass = ENV["GIT_FIT_KEEP_PASSWORD"]
  cfg_phone = cfg_pass = nil
  if File.exist?("config.yml")
    y = begin
      YAML.safe_load_file("config.yml")
    rescue
      {}
    end
    cfg_phone = y.dig("sync", "keep", "phone") || y.dig("sync", "keep", "mobile")
    cfg_pass = y.dig("sync", "keep", "password")
  end
  load_dot_env(".env")
  load_dot_env(".env.local")
  cfg_phone ||= ENV["GIT_FIT_KEEP_PHONE"]
  cfg_pass ||= ENV["GIT_FIT_KEEP_PASSWORD"]
  [cfg_phone || env_phone, cfg_pass || env_pass]
end

def load_dot_env(path)
  return unless File.exist?(path)
  File.foreach(path) do |line|
    line.strip!
    next if line.empty? || line.start_with?("#")
    k, v = line.split("=", 2)
    next unless k && v
    ENV[k] ||= v
  end
end

def http_post(url, body, headers = {})
  uri = URI(url)
  req = Net::HTTP::Post.new(uri)
  headers.each { |k, v| req[k] = v }
  req.body = URI.encode_www_form(body)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) { |h| h.request(req) }
end

def http_get(url, headers = {})
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  headers.each { |k, v| req[k] = v }
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) { |h| h.request(req) }
end

def aes_decrypt(data)
  c = OpenSSL::Cipher.new("AES-128-CBC")
  c.decrypt
  c.key = AES_KEY
  c.iv = AES_IV
  c.update(data) + c.final
end

def zlib_inflate(data)
  [-Zlib::MAX_WBITS, Zlib::MAX_WBITS, Zlib::MAX_WBITS + 16].each do |w|
    inf = Zlib::Inflate.new(w)
    r = inf.inflate(data)
    begin
      inf.finish
    rescue
      nil
    end
    inf.close
    return r
  rescue Zlib::DataError
    next
  end
  raise Zlib::DataError, "inflate failed"
end

def decode_geo_points(b64)
  return nil unless b64
  raw = Base64.decode64(b64)
  dec = aes_decrypt(raw)
  js = zlib_inflate(dec)
  JSON.parse(js)
rescue => e
  warn "decode_geo_points failed: #{e.class} #{e.message}"
  nil
end

def decode_hr_data(b64)
  return nil unless b64
  raw = Base64.decode64(b64)
  js = zlib_inflate(raw)
  JSON.parse(js)
rescue => e
  warn "decode_hr_data failed: #{e.class} #{e.message}"
  nil
end

phone, password = load_config
phone = options[:phone] if options[:phone]
password = options[:password] if options[:password]

abort "missing phone/password (config.yml sync.keep.phone/password or --phone/--password)" unless phone && password

headers = {
  "User-Agent" => "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:78.0) Gecko/20100101 Firefox/78.0",
  "Content-Type" => "application/x-www-form-urlencoded;charset=utf-8"
}

puts "login #{phone} ..."
resp = http_post(LOGIN_URL, {mobile: phone, password: password}, headers)
abort "login failed http=#{resp.code} body=#{resp.body[0, 800]}" unless resp.code.to_i == 200
j = begin
  JSON.parse(resp.body)
rescue
  abort("login JSON parse failed: #{resp.body[0, 800]}")
end
token = j.dig("data", "token")
abort "login no token: #{resp.body[0, 800]}" unless token
headers["Authorization"] = "Bearer #{token}"
puts "login ok token=#{token[0, 20]}..."

out_dir = options[:out] || "tmp"
FileUtils.mkdir_p(out_dir)

def find_compound_for_numeric(numeric, headers)
  SPORTS.each do |sport|
    last_date = 0
    loop do
      url = "https://api.gotokeep.com/pd/v3/stats/detail?dateUnit=all&type=#{sport}&lastDate=#{last_date}"
      r = http_get(url, headers)
      break unless r.code.to_i == 200
      j = begin
        JSON.parse(r.body)
      rescue
        break
      end
      data = j["data"]
      break unless data
      (data["records"] || []).each do |rec|
        (rec["logs"] || []).each do |log|
          stats = log["stats"] || log
          cid = stats["id"]
          next unless cid
          if cid.include?(numeric)
            return [sport, cid]
          end
        end
      end
      last_date = data["lastTimestamp"]
      break if last_date.nil? || last_date.zero?
      sleep 0.1
    end
  end
  nil
end

puts "\nsearching compound_id for numeric #{RUN_ID} via stats/detail ..."
found = find_compound_for_numeric(RUN_ID, headers)
if found
  puts " found via stats: sport=#{found[0]} compound=#{found[1]}"
end

success = false
# prioritize discovered compound, then fallback candidates
candidates_by_sport = {}
if found
  candidates_by_sport[found[0]] = [found[1]]
else
  SPORTS.each { |s| candidates_by_sport[s] = [RUN_ID, "#{s}_#{RUN_ID}", "#{s}log_#{RUN_ID}"] }
end

candidates_by_sport.each do |sport, candidates|
  candidates.uniq.each do |cid|
    url = LOG_URL_TMPL % {sport: sport, compound_id: cid}
    puts "\nGET #{url}"
    r = http_get(url, headers)
    puts " -> http #{r.code}"
    if r.code.to_i != 200
      puts " body: #{r.body[0, 400]}"
      next
    end
    raw_body = r.body
    raw_path = File.join(out_dir, "keep_#{RUN_ID}_raw.json")
    File.write(raw_path, raw_body)
    puts " saved raw -> #{raw_path} (#{raw_body.bytesize} bytes)"

    parsed = begin
      JSON.parse(raw_body)
    rescue
      nil
    end
    unless parsed
      warn " raw not JSON"
      next
    end
    data = parsed["data"]
    unless data
      warn " no data field: #{raw_body[0, 800]}"
      next
    end

    # decode payload
    gp = data["geoPoints"]
    hr = data.dig("heartRate", "heartRates")
    geo_points = decode_geo_points(gp)
    hr_data = decode_hr_data(hr)

    puts " decoded geoPoints=#{geo_points&.size || "nil"} hrData=#{hr_data&.size || "nil"}"

    decrypted = {
      "source" => "keep",
      "fetchedAt" => Time.now.utc.iso8601,
      "run_id" => RUN_ID,
      "compound_id" => cid,
      "sport" => sport,
      "url" => url,
      "meta" => {
        "id" => data["id"],
        "startTime" => data["startTime"],
        "endTime" => data["endTime"],
        "duration" => data["duration"],
        "dataType" => data["dataType"],
        "distance" => data["distance"],
        "region" => data["region"],
        "elevation" => data["elevation"]
      },
      "rawDataKeys" => data.keys,
      "geoPoints" => geo_points,
      "heartRates" => hr_data,
      "rawHeartRate" => data["heartRate"],
      "rawGeoPoints_b64_len" => gp&.length,
      "rawHr_b64_len" => hr&.length
    }

    dec_path = File.join(out_dir, "keep_#{RUN_ID}_decrypted.json")
    File.write(dec_path, JSON.pretty_generate(decrypted))
    puts " saved decrypted -> #{dec_path} (geo=#{geo_points&.size} hr=#{hr_data&.size})"

    # also keep a pretty raw copy for diff
    payload_path = File.join(out_dir, "keep_#{RUN_ID}_payload.json")
    File.write(payload_path, JSON.pretty_generate(parsed))
    puts " saved payload pretty -> #{payload_path}"

    success = true
    break
  end
  break if success
end

abort "all candidates failed for #{RUN_ID}" unless success
puts "\ndone. files in #{out_dir}/keep_#{RUN_ID}_*.json"

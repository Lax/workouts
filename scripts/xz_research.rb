require "bundler/setup"
require "workouts"

IDS = {
  trail: { id: 55976106, name: "2018-11-03 越野", pts: 1166 },
  ride:  { id: 56279644, name: "2018-11-30 骑行", pts: 5157 },
}

cfg = Workouts::Config.new.dig("sync", "xingzhe")
abort "No xingzhe credentials in config" unless cfg

class Workouts::Sync::XingZhe
  public :login
end

xz = Workouts::Sync::XingZhe.new(config: cfg, db: nil, activity_filter: nil)
xz.login
headers = xz.instance_variable_get(:@headers)

def fetch(path, headers)
  uri = URI("https://www.imxingzhe.com#{path}")
  req = Net::HTTP::Get.new(uri)
  headers.each { |k, v| req[k] = v }
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 30
  http.read_timeout = 60
  resp = http.start { |h| h.request(req) }
  [resp.code.to_i, resp.body]
rescue => e
  [0, "ERROR: #{e}"]
end

FileUtils.mkdir_p("spec/fixtures/xingzhe")

IDS.each do |key, info|
  id = info[:id]
  base = "spec/fixtures/xingzhe/#{id}_#{key}"

  code, body = fetch("/api/v1/pgworkout/#{id}/", headers)
  File.write("#{base}_detail.json", body) if code == 200
  puts "#{key} detail: #{code}"

  code, body = fetch("/api/v1/pgworkout/#{id}/gpx/", headers)
  File.write("#{base}.gpx", body) if code == 200
  puts "#{key} gpx: #{code} #{body.bytesize}b"

  code, body = fetch("/api/v1/pgworkout/#{id}/stream/", headers)
  File.write("#{base}_stream.json", body) if code == 200
  puts "#{key} stream: #{code} #{body.bytesize}b"
end

puts "\nFixtures in spec/fixtures/xingzhe/:"
Dir["spec/fixtures/xingzhe/*"].each { |f| puts "  #{f} (#{File.size(f)}b)" }

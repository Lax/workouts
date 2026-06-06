Gem::Specification.new do |s|
  s.name        = "workouts-cli"
  s.version     = "0.1.0"
  s.summary     = "Workouts — Yet Another Training Aggregator"
  s.description = "Sync workout data from Strava, Garmin, Keep, iGPSPORT, XOSS and more. Generate JSON and SVG posters."
  s.authors     = ["Lax"]
  s.homepage    = "https://github.com/lax/workouts"
  s.license     = "MIT"

  s.files       = Dir["lib/**/*", "db/**/*", "config/**/*"]
  s.bindir      = "exe"
  s.executables = ["workouts"]

  s.required_ruby_version = ">= 3.1"

  s.add_dependency "thor", "~> 1.3"
  s.add_dependency "sequel", "~> 5.0"
  s.add_dependency "sqlite3", "~> 2.0"
  s.add_dependency "faraday", "~> 2.0"
  s.add_dependency "faraday-multipart", "~> 1.0"
  s.add_dependency "faraday-cookie_jar", "~> 0.0"
  s.add_dependency "csv", "~> 3.0"
  s.add_dependency "base64", "~> 0.2"
  s.add_dependency "zlib", "~> 3.0"
  s.add_dependency "openssl", "~> 3.0"
  s.add_dependency "nokogiri", "~> 1.16"
  s.add_dependency "oauth", "~> 1.0"
  s.add_dependency "mini_racer", "~> 0.16"
end
